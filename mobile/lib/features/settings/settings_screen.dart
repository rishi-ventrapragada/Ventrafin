import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../lock/lock_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _toggleFingerprint(BuildContext context, WidgetRef ref, bool enable) async {
    if (enable) {
      // Only switch on after one successful scan.
      final ok = await ref
          .read(localAuthProvider)
          .authenticate(localizedReason: 'Confirm your fingerprint for Ventrafin', biometricOnly: true)
          .catchError((_) => false);
      if (!ok) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fingerprint wasn't confirmed.")));
        }
        return;
      }
    }
    await ref.read(lockControllerProvider.notifier).setBiometricEnabled(enable);
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('Your data stays in your account. Sign in with Google to come back.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true) await ref.read(lockControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(currentUserProvider)?.email ?? '';
    final available = ref.watch(biometricsAvailableProvider).value ?? false;
    final enabled = ref.watch(biometricEnabledProvider).value ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(leading: const Icon(Icons.account_circle), title: const Text('Signed in with Google'), subtitle: Text(email)),
          const Divider(),
          ListTile(title: Text('App lock', style: Theme.of(context).textTheme.titleSmall)),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Unlock with fingerprint'),
            subtitle: Text(available ? 'Pattern stays available as a backup' : 'No fingerprint set up on this phone'),
            value: enabled && available,
            onChanged: available ? (v) => _toggleFingerprint(context, ref, v) : null,
          ),
          ListTile(
            leading: const Icon(Icons.pattern),
            title: const Text('Change unlock pattern'),
            onTap: () => context.push('/more/settings/change-pattern'),
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Auto-lock'),
            subtitle: Text('When the app is reopened after ${kRelockAfterBackground.inSeconds} seconds in the background'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () => _signOut(context, ref),
          ),
          const ListTile(
            leading: Icon(Icons.palette_outlined),
            title: Text('Theme'),
            subtitle: Text('Ocean. More themes are coming in a later update.'),
          ),
        ],
      ),
    );
  }
}
