import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/consent_dialog.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/session.dart';
import 'theme.dart';
import 'widgets/common.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.isConfigured) {
    await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseKey);
  }
  runApp(const Bytebox());
}

class Bytebox extends StatelessWidget {
  const Bytebox({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        navigatorKey: navigatorKey,
        home: const BootScreen(),
      );
}

/// Guest sign-in → install recorded → consent → Explore. No login screen at start.
class BootScreen extends StatefulWidget {
  const BootScreen({super.key});
  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    if (!AppConfig.isConfigured) return;
    _authSub = db.auth.onAuthStateChange.listen((s) {
      final ctx = navigatorKey.currentContext;
      if (s.event == AuthChangeEvent.passwordRecovery && ctx != null) {
        showSetNewPassword(ctx);
      }
      if (s.event == AuthChangeEvent.signedIn && session.ready && s.session?.user.isAnonymous == false) {
        session.onExternalSignIn();
      }
    });
    _start();
  }

  Future<void> _start() async {
    await session.boot();
    if (!mounted || session.bootError != null) {
      setState(() {});
      return;
    }
    if (!mounted) return;
    if (!session.consentAccepted) await showConsentDialog(context);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, _, _) => const HomeShell(),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.isConfigured) {
      return const Scaffold(body: EmptyState(text: 'This build is missing its server configuration.'));
    }
    return Scaffold(
      body: Center(
        child: session.bootError != null
            ? ErrorRetry(message: session.bootError!, onRetry: () {
                setState(() => session.bootError = null);
                _start();
              })
            : const Column(mainAxisSize: MainAxisSize.min, children: [
                BrandMark(size: 96),
                SizedBox(height: 24),
                SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.6)),
              ]),
      ),
    );
  }
}
