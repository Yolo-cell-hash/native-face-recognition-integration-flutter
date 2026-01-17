package com.gnb.edge_based_ai

import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private val TAG = "MainActivity"

    override fun onCreate(savedInstanceState: Bundle?) {
        Log.d(TAG, "🚀 MainActivity: onCreate called")
        Log.d(TAG, "🚀 MainActivity: Android SDK version: ${Build.VERSION.SDK_INT}")
        
        super.onCreate(savedInstanceState)
        
        // Set lock screen flags for Android O (API 27) and above
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            Log.d(TAG, "🔓 MainActivity: Setting lock screen flags (API 27+)")
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            Log.d(TAG, "✅ MainActivity: Lock screen flags set via methods")
        } else {
            // For older Android versions, use window flags
            Log.d(TAG, "🔓 MainActivity: Setting lock screen flags via window (API < 27)")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
            Log.d(TAG, "✅ MainActivity: Lock screen flags set via window flags")
        }
        
        Log.d(TAG, "✅ MainActivity: Initialization complete")
    }

    override fun onResume() {
        super.onResume()
        Log.d(TAG, "📱 MainActivity: onResume called")
    }

    override fun onPause() {
        super.onPause()
        Log.d(TAG, "📱 MainActivity: onPause called")
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "📱 MainActivity: onDestroy called")
    }
}
