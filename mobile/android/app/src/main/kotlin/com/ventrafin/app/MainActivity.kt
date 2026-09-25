package com.ventrafin.app

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not FlutterActivity) is required by local_auth,
// whose fingerprint prompt is an AndroidX BiometricPrompt fragment.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Privacy: the app's content never appears in the recent-apps
        // screen, in screenshots or in screen recordings/casting. Set before
        // the first frame so not even the launch frame can be captured.
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Android 13+: also skip the recents thumbnail snapshot outright.
            setRecentsScreenshotEnabled(false)
        }
        super.onCreate(savedInstanceState)
    }
}
