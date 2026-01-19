package com.gnb.edge_based_ai

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Home Widget Provider for quick access to face verification
 * Supports both home screen and lock screen (keyguard) placement
 */
class HomeWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val TAG = "🔷 HomeWidget"
        private const val WIDGET_CLICK_ACTION = "com.gnb.edge_based_ai.WIDGET_CLICK"
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        Log.d(TAG, "onUpdate called for ${appWidgetIds.size} widgets")
        
        for (appWidgetId in appWidgetIds) {
            Log.d(TAG, "Updating widget ID: $appWidgetId")
            updateWidget(context, appWidgetManager, appWidgetId)
        }
        
        super.onUpdate(context, appWidgetManager, appWidgetIds)
    }

    override fun onEnabled(context: Context) {
        Log.d(TAG, "Widget enabled - first widget added to home screen")
        super.onEnabled(context)
    }

    override fun onDisabled(context: Context) {
        Log.d(TAG, "Widget disabled - last widget removed from home screen")
        super.onDisabled(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        Log.d(TAG, "Widget(s) deleted: ${appWidgetIds.size} widgets removed")
        super.onDeleted(context, appWidgetIds)
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "onReceive: ${intent.action}")
        
        when (intent.action) {
            WIDGET_CLICK_ACTION -> {
                Log.d(TAG, "Widget click detected!")
                handleWidgetClick(context)
            }
            else -> {
                super.onReceive(context, intent)
            }
        }
    }

    /**
     * Update a single widget instance
     */
    private fun updateWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        Log.d(TAG, "Building RemoteViews for widget $appWidgetId")
        
        // Get widget data from shared preferences (set by Flutter)
        val widgetData = HomeWidgetPlugin.getData(context)
        val status = widgetData.getString("verification_status", "Tap to verify")
        val lastTime = widgetData.getString("last_verification_time", "Never")
        
        Log.d(TAG, "Widget data - Status: '$status', Time: '$lastTime'")
        
        // Create the RemoteViews object
        val views = RemoteViews(context.packageName, R.layout.home_widget_layout)
        
        // Update text fields
        views.setTextViewText(R.id.widget_status, status)
        views.setTextViewText(R.id.widget_time, lastTime)
        
        Log.d(TAG, "Setting widget click action")
        
        // Create click intent with deep link
        val clickIntent = Intent(Intent.ACTION_VIEW).apply {
            data = Uri.parse("edgebasedai://verify")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        
        val pendingIntent = PendingIntent.getActivity(
            context,
            appWidgetId,
            clickIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // Set click listener on the entire widget
        views.setOnClickPendingIntent(R.id.widget_click_area, pendingIntent)
        
        Log.d(TAG, "Updating widget UI for ID: $appWidgetId")
        
        // Update the widget
        appWidgetManager.updateAppWidget(appWidgetId, views)
        
        Log.d(TAG, "✅ Widget $appWidgetId updated successfully")
    }

    /**
     * Handle widget click events
     */
    private fun handleWidgetClick(context: Context) {
        Log.d(TAG, "Processing widget click - launching app...")
        
        try {
            // Create intent to open the app with deep link
            val launchIntent = Intent(Intent.ACTION_VIEW).apply {
                data = Uri.parse("edgebasedai://verify")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            
            context.startActivity(launchIntent)
            Log.d(TAG, "✅ App launch intent sent successfully")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to launch app from widget click: ${e.message}", e)
        }
    }
}
