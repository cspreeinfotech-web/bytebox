/// Build-time configuration (passed with --dart-define in CI). Nothing secret lives here:
/// the publishable key is designed to ship inside apps; all rules are enforced in the database.
class AppConfig {
  static const appName = 'Bytebox';
  static const shortCode = 'BB';
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Referrer baked into the Meta-ads APK, e.g. utm_source=meta&utm_medium=paid_social&...
  static const apkReferrer = String.fromEnvironment('APK_REFERRER');

  /// true for the Google Play AAB: no UPI, no prices, 15 GB free cloud for logged-in users.
  static const playStore = bool.fromEnvironment('PLAY_STORE');
  static const androidAppId = String.fromEnvironment('ANDROID_APP_ID', defaultValue: 'com.bytebox.app');

  static const websiteUrl = String.fromEnvironment('WEBSITE_URL', defaultValue: 'https://bytebox-ejim.vercel.app');
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL', defaultValue: 'cs.preeinfotech@gmail.com');

  static String get loginCallback => '$androidAppId://login-callback';
  static const consentVersion = 'v1';
  static const signedUrlSeconds = 3600;
  static const maxUploadBytes = 50 * 1024 * 1024;

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
