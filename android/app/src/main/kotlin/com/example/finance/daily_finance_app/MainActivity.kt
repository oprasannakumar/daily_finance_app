package com.example.finance.daily_finance_app

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.finance/widget_channel"
    private var channel: MethodChannel? = null
    private var pendingAction: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialAction" -> {
                    result.success(pendingAction)
                    pendingAction = null
                }
                "updateWidgetBalances" -> {
                    val jsonStr = call.arguments as? String
                    if (jsonStr != null) {
                        saveAndRefreshWidget(jsonStr)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        pendingAction?.let {
            channel?.invokeMethod("onWidgetAction", it)
            pendingAction = null
        }
    }

    private fun saveAndRefreshWidget(jsonStr: String) {
        val prefs = getSharedPreferences("SmartLedgerWidgetPrefs", Context.MODE_PRIVATE)
        prefs.edit().putString("balances_json", jsonStr).apply()

        val appWidgetManager = AppWidgetManager.getInstance(this)
        val componentName = ComponentName(this, SmartLedgerWidgetProvider::class.java)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
        for (id in appWidgetIds) {
            SmartLedgerWidgetProvider.updateAppWidgetStatic(this, appWidgetManager, id)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val action = intent?.action ?: return
        if (action.startsWith("action_")) {
            if (channel != null) {
                channel?.invokeMethod("onWidgetAction", action)
            } else {
                pendingAction = action
            }
        }
    }
}
