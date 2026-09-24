package com.ventrafin.app

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not FlutterActivity) is required by local_auth,
// whose fingerprint prompt is an AndroidX BiometricPrompt fragment.
class MainActivity : FlutterFragmentActivity()
