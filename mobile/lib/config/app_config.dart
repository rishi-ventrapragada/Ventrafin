/// Build-time configuration, supplied with
/// `--dart-define-from-file=config/dev.json` (see mobile/README.md).
///
/// Nothing here is hardcoded or committed: `config/*.json` is gitignored and
/// only `config/example.json` (placeholders) is in the repo.
class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.googleWebClientId,
  });

  /// Reads the values compiled in via --dart-define(-from-file).
  factory AppConfig.fromEnvironment() => const AppConfig(
        supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
        supabasePublishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
        googleWebClientId: String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
      );

  final String supabaseUrl;

  /// The anon/publishable key. Public by design: RLS is what protects data.
  /// Never put the service_role / secret key here.
  final String supabasePublishableKey;

  /// The **Web** OAuth client id. Native Google Sign-In asks Google for an ID
  /// token addressed to this client, which Supabase then verifies.
  final String googleWebClientId;

  /// Human-readable problems, empty when the config is usable.
  List<String> get problems {
    final issues = <String>[];
    final uri = Uri.tryParse(supabaseUrl);
    if (supabaseUrl.isEmpty) {
      issues.add('SUPABASE_URL is missing.');
    } else if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      issues.add('SUPABASE_URL must be an https:// URL.');
    }
    if (supabasePublishableKey.isEmpty) {
      issues.add('SUPABASE_PUBLISHABLE_KEY is missing.');
    } else if (supabasePublishableKey.startsWith('sb_secret_')) {
      issues.add('SUPABASE_PUBLISHABLE_KEY is a SECRET key. Use the publishable (anon) key.');
    }
    if (googleWebClientId.isEmpty) {
      issues.add('GOOGLE_WEB_CLIENT_ID is missing.');
    } else if (!googleWebClientId.endsWith('.apps.googleusercontent.com')) {
      issues.add('GOOGLE_WEB_CLIENT_ID does not look like a Google OAuth client id.');
    }
    return issues;
  }

  bool get isValid => problems.isEmpty;
}
