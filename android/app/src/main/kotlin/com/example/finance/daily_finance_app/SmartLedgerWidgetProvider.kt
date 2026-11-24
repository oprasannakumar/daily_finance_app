package com.example.finance.daily_finance_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class SmartLedgerWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    private fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
        val views = RemoteViews(context.packageName, R.layout.smart_ledger_widget_layout)

        // 1. Quick Add PendingIntent
        val addIntent = Intent(context, MainActivity::class.java).apply {
            action = "action_quick_add"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val addPending = PendingIntent.getActivity(
            context, 101, addIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.btn_quick_add, addPending)

        // 2. Scan Bill PendingIntent
        val scanIntent = Intent(context, MainActivity::class.java).apply {
            action = "action_scan_receipt"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val scanPending = PendingIntent.getActivity(
            context, 102, scanIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.btn_scan_receipt, scanPending)

        // 3. Borrowers PendingIntent
        val borrIntent = Intent(context, MainActivity::class.java).apply {
            action = "action_borrowers"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val borrPending = PendingIntent.getActivity(
            context, 103, borrIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.btn_borrowers, borrPending)

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }
}
