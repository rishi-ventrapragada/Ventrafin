import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import 'auth_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    if (!ref.read(isOnlineProvider)) {
      setState(() => _error = 'No internet connection. Connect and try again.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
      // The router moves on once the session arrives.
    } on SignInCancelled {
      // Account picker closed: nothing to report.
    } on GoogleSignInException catch (e) {
      _error = switch (e.code) {
        GoogleSignInExceptionCode.clientConfigurationError || GoogleSignInExceptionCode.providerConfigurationError =>
          'Google Sign-In is not set up for this app build yet (Android OAuth client / SHA-1). '
              'Details: ${e.description ?? e.code.name}',
        _ => 'Google Sign-In failed: ${e.description ?? e.code.name}',
      };
    } catch (e) {
      _error = describeError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.account_balance_wallet, size: 64, color: kOceanPrimary),
                const SizedBox(height: 12),
                Text('Ventrafin', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text('Your home finances, on phone and PC', style: theme.textTheme.bodyMedium),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _busy ? null : _signIn,
                  icon: _busy
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.login),
                  label: const Text('Sign in with Google'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 32),
                Text(
                  'Only you can see your data in the app.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
