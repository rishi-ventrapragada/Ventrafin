import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// True when [error] means "couldn't reach the server" rather than "the
/// server said no". Drives the "no internet" wording.
bool isNetworkError(Object error) =>
    error is SocketException ||
    error is TimeoutException ||
    error is HandshakeException ||
    error is http.ClientException ||
    error is AuthRetryableFetchException;

/// A short, plain-language explanation for the person using the app.
/// Technical details stay in the exception, not on screen.
String describeError(Object error) {
  if (isNetworkError(error)) {
    return "Couldn't reach the server. Check your internet connection and try again.";
  }
  if (error is PostgrestException) {
    switch (error.code) {
      case '42501':
        return "You don't have permission to do that. Try signing out and back in.";
      case '23505':
        return 'That name is already used. Pick a different one.';
      case '23503':
        return 'That account or category no longer exists. Pick another one and try again.';
      case '23514':
        return 'Some values were not accepted (for example an amount of zero or a missing destination account).';
      case 'PGRST301':
      case 'PGRST303':
        return 'Your session has expired. Please sign in again.';
    }
    return 'The server rejected the change (${error.code ?? 'error'}).';
  }
  if (error is AuthException) {
    return 'Sign-in problem: ${error.message}';
  }
  return 'Something went wrong. Please try again.';
}
