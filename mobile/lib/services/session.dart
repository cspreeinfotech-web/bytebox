import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';
import 'native.dart';

SupabaseClient get db => Supabase.instance.client;

/// Human-readable message from any Supabase / platform error.
String friendlyError(Object e) {
  if (e is PostgrestException) return e.message;
  if (e is AuthException) return e.message;
  if (e is StorageException) return e.message;
  if (e is FunctionException) {
    final d = e.details;
    return (d is Map && d['error'] != null) ? '${d['error']}' : (e.reasonPhrase ?? 'Request failed');
  }
  if (e is SocketException) return 'No internet connection. Please try again.';
  final s = e.toString();
  return s.startsWith('Exception: ') ? s.substring(11) : s;
}

/// App-wide state: guest account, install attribution, consent, my_status, app mode, plans.
class AppSession extends ChangeNotifier {
  AppSession._();
  static final AppSession instance = AppSession._();

  static const _kInstallId = 'install_id';
  static const _kInstallSecret = 'install_secret';

  late SharedPreferences prefs;
  String installId = '';
  String _installSecret = '';

  bool ready = false;
  String? bootError;
  bool consentAccepted = false;
  Map<String, dynamic> status = {};
  bool freeMode = false;
  bool playBilling = false; // User Choice Billing (Play build) — server flag, OFF by default
  /// Bumped whenever plans, app mode or payment settings change on the server (Realtime).
  int settingsVersion = 0;
  RealtimeChannel? _live;

  /// Hooks run after boot and after every account switch (e.g. pending UPI result retry).
  final List<Future<void> Function()> afterAuthHooks = [];

  // ------------------------------------------------------------------ getters
  User? get user => db.auth.currentUser;
  bool get isGuest => user == null || (user!.isAnonymous) || status['is_guest'] == true;
  bool get isLoggedIn => !isGuest;
  String get displayName => (status['display_name'] as String?) ?? 'Guest';
  String? get email => status['email'] as String?;
  String get source => (status['source'] as String?) ?? 'organic';
  bool get isAdsUser => source == 'ads';
  bool get hasAdsAccess => status['has_ads_access'] == true;
  String get accessStatus => (status['ads_access_status'] as String?) ?? 'none';
  bool get isPremium => status['is_premium'] == true;
  Map<String, dynamic>? get plan => status['plan'] as Map<String, dynamic>?;
  Map<String, dynamic>? get openOrder => status['open_order'] as Map<String, dynamic>?;
  int get quotaBytes => (status['quota_bytes'] as num?)?.toInt() ?? 0;
  int get usedBytes => (status['used_bytes'] as num?)?.toInt() ?? 0;
  bool get ownsApprovedChannel => status['owns_approved_channel'] == true;

  /// Free experience: free mode switched on by the owner, or the Google Play build
  /// (unless User Choice Billing has been switched on for it).
  bool get noPayments => freeMode || (AppConfig.playStore && !playBilling);

  /// Google Play build without Play billing: never show prices or content that can't be unlocked in-app
  /// (Play Payments policy). Plans that are free for this user are still shown.
  bool get hidePaid => AppConfig.playStore && !playBilling;

  // --------------------------------------------------------------------- boot
  Future<void> boot() async {
    bootError = null;
    try {
      prefs = await SharedPreferences.getInstance();
      installId = prefs.getString(_kInstallId) ?? '';
      _installSecret = prefs.getString(_kInstallSecret) ?? '';
      if (installId.isEmpty || _installSecret.length < 16) {
        installId = const Uuid().v4();
        final r = Random.secure();
        _installSecret = base64Url.encode(List<int>.generate(32, (_) => r.nextInt(256)));
        await prefs.setString(_kInstallId, installId);
        await prefs.setString(_kInstallSecret, _installSecret);
      }

      if (db.auth.currentSession == null) {
        await db.auth.signInAnonymously();
      }
      await _recordInstall();
      await Future.wait([refresh(), _loadMode(), _loadConsent()]);
      _subscribeLive();
      await _runHooks();
      ready = true;
    } catch (e) {
      bootError = friendlyError(e);
    }
    notifyListeners();
  }

  Future<void> _recordInstall() async {
    final device = await Native.deviceInfo();
    await db.rpc('record_install', params: {
      'p_install_id': installId,
      'p_install_secret': _installSecret,
      'p_referrer': AppConfig.apkReferrer.isEmpty ? null : AppConfig.apkReferrer,
      'p_device': device,
    });
    if (AppConfig.playStore) {
      await db.rpc('enable_play_free_cloud');
    }
  }

  Future<void> _attribute() async {
    await db.rpc('attribute_user', params: {'p_install_id': installId, 'p_install_secret': _installSecret});
    if (AppConfig.playStore) await db.rpc('enable_play_free_cloud');
  }

  Future<void> _runHooks() async {
    for (final h in afterAuthHooks) {
      try {
        await h();
      } catch (e) {
        debugPrint('hook failed: $e');
      }
    }
  }

  Future<void> refresh() async {
    final s = await db.rpc('my_status');
    status = (s as Map?)?.cast<String, dynamic>() ?? {};
    notifyListeners();
  }

  Future<void> _loadMode() async {
    final row = await db.from('app_mode').select('free_mode, play_billing_enabled').eq('id', 1).maybeSingle();
    freeMode = row?['free_mode'] == true;
    playBilling = row?['play_billing_enabled'] == true;
  }

  Future<void> _loadConsent() async {
    final local = prefs.getBool('consent_${AppConfig.consentVersion}_${user?.id}') ?? false;
    if (local) {
      consentAccepted = true;
      return;
    }
    final row = await db.from('consents').select('id').eq('version', AppConfig.consentVersion).maybeSingle();
    consentAccepted = row != null;
  }

  Future<void> acceptConsent() async {
    final device = await Native.deviceInfo();
    await db.rpc('record_consent', params: {
      'p_version': AppConfig.consentVersion,
      'p_documents': ['privacy', 'terms', 'refund', 'community'],
      'p_install_id': installId,
      'p_device': device,
    });
    await prefs.setBool('consent_${AppConfig.consentVersion}_${user?.id}', true);
    consentAccepted = true;
    notifyListeners();
  }

  void _subscribeLive() {
    _live?.unsubscribe();
    _live = db
        .channel('public:app-live')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_mode',
          callback: (_) => _settingsChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'plans',
          callback: (_) => _settingsChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'settings_version',
          callback: (_) => _settingsChanged(),
        )
        .subscribe();
  }

  Future<void> _settingsChanged() async {
    settingsVersion++;
    try {
      await _loadMode();
      await refresh();
    } catch (_) {
      notifyListeners();
    }
  }

  bool get paymentsAvailable => status['payments_available'] == true;
  String get freePlansFor => (status['free_plans_for'] as String?) ?? 'none';

  // --------------------------------------------------------------------- auth
  /// Guest → account keeps the SAME user id (and attribution).
  Future<void> createAccount(String email, String password) async {
    if (user != null && user!.isAnonymous) {
      await db.auth.updateUser(UserAttributes(email: email.trim(), password: password));
    } else {
      await db.auth.signUp(email: email.trim(), password: password);
    }
    await _afterLogin();
  }

  /// Logging into an existing account switches to that account.
  Future<void> logIn(String email, String password) async {
    await db.auth.signInWithPassword(email: email.trim(), password: password);
    await _afterLogin();
  }

  Future<void> forgotPassword(String email) =>
      db.auth.resetPasswordForEmail(email.trim(), redirectTo: AppConfig.loginCallback);

  /// Returns false when the Google provider is switched off in Supabase.
  Future<bool> googleEnabled() async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(Uri.parse('${AppConfig.supabaseUrl}/auth/v1/settings'));
      req.headers.set('apikey', AppConfig.supabaseKey);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close();
      final json = jsonDecode(body) as Map<String, dynamic>;
      return (json['external'] as Map?)?['google'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> signInWithGoogle() async {
    await db.auth.signInWithOAuth(OAuthProvider.google, redirectTo: AppConfig.loginCallback);
  }

  /// Called by main.dart when an OAuth / recovery deep link signs the user in.
  Future<void> onExternalSignIn() => _afterLogin();

  Future<void> _afterLogin() async {
    await _attribute();
    await _loadConsentQuiet();
    await refresh();
    await _runHooks();
  }

  Future<void> _loadConsentQuiet() async {
    try {
      await _loadConsent();
      if (!consentAccepted) await acceptConsent(); // consent was given on this device before login
    } catch (_) {}
  }

  /// Logout → a fresh guest account on the same install.
  Future<void> logOut() async {
    await db.auth.signOut();
    await db.auth.signInAnonymously();
    await _attribute();
    await _loadConsentQuiet();
    await refresh();
  }

  Future<void> setDisplayName(String name) async {
    await db.rpc('set_display_name', params: {'p_name': name});
    await refresh();
  }

  Future<String> requestFullAccess() async {
    final r = await db.rpc('request_full_access');
    await refresh();
    return r as String;
  }
}

final session = AppSession.instance;
