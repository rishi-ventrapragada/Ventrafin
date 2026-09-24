import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'entry_form.dart';

/// Bottom-nav "Add": batch entry.
class AddScreen extends StatelessWidget {
  const AddScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add transaction')),
      body: EntryForm(
        onSavedAndClose: (_) => GoRouter.maybeOf(context)?.go('/transactions'),
      ),
    );
  }
}
