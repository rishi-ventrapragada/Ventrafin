import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/providers.dart';

/// Thrown when the user closes the Google account picker. Not an error worth
/// showing.
class SignInCancelled implements Exception {
  const SignInCancelled();
}

/// Google Sign-In for Android without a browser redirect:
///   1. Android Credential Manager shows the Google account picker.
///   2. Google returns an ID token addressed to the **Web** client id
///      (`serverClientId`). It only does so for an app whose package name and
///      signing-certificate SHA-1 match an Android OAuth client in the same
///      Google Cloud project.
///   3. Supabase verifies that token (`signInWithIdToken`) and creates the
///      session. On first sign-in the database seeds the profile, categories
///      and accounts.
class AuthService {
  AuthService(this._client, this._webClientId);

  final SupabaseClient _client;
  final String _webClientId;
  Future<void>? _initialized;

  static const _scopes = ['email', 'profile'];

  Future<void> _ensureInitialized() =>
      _initialized ??= GoogleSignIn.instance.initialize(serverClientId: _webClientId);

  Future<void> signInWithGoogle() async {
    await _ensureInitialized();

    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate(scopeHint: _scopes);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) throw const SignInCancelled();
      rethrow;
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthException('Google did not return an ID token. Check the Android OAuth client setup.');
    }

    try {
      await _client.auth.signInWithIdToken(provider: OAuthProvider.google, idToken: idToken);
    } on AuthException catch (e) {
      // Some Google tokens carry an at_hash claim; Supabase then also wants
      // the matching access token. Fetch it (interactively if needed) and retry.
      if (!e.message.toLowerCase().contains('access token')) rethrow;
      final authorization = await account.authorizationClient.authorizationForScopes(_scopes) ??
          await account.authorizationClient.authorizeScopes(_scopes);
      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: authorization.accessToken,
      );
    }
  }

  /// Signs out of Supabase and Google, so the next sign-in shows the account
  /// picker again (needed for "Forgot pattern?", D6).
  Future<void> signOut() async {
    try {
      await _ensureInitialized();
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Google sign-out is best-effort; the Supabase sign-out below is what
      // actually ends access to the data.
    }
    await _client.auth.signOut(scope: SignOutScope.local);
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(supabaseClientProvider), ref.watch(appConfigProvider).googleWebClientId);
});
