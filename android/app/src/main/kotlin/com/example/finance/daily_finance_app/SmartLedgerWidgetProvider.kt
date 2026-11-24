package com.example.finance.daily_finance_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.NumberFormat
import java.util.Locale

class SmartLedgerWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidgetStatic(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        fun formatInr(value: Double): String {
            return try {
                val format = NumberFormat.getCurrencyInstance(Locale("en", "IN"))
                format.maximumFractionDigits = if (value % 1.0 == 0.0) 0 else 2
                format.format(value)
            } catch (e: Exception) {
                "₹" + String.format("%.0f", value)
            }
        }

        fun updateAppWidgetStatic(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.smart_ledger_widget_layout)

            val prefs = context.getSharedPreferences("SmartLedgerWidgetPrefs", Context.MODE_PRIVATE)
            val jsonStr = prefs.getString("balances_json", null)

            var bankCount = 0
            var cardCount = 0
            var totalCash = 0.0

            if (jsonStr != null && jsonStr.isNotEmpty()) {
                try {
                    val obj = JSONObject(jsonStr)

                    val totalBankCash = obj.optDouble("totalBankCash", 0.0)
                    val totalCreditAvail = obj.optDouble("totalCreditAvail", 0.0)
                    val totalCreditLimit = obj.optDouble("totalCreditLimit", 0.0)
                    totalCash = obj.optDouble("totalCash", 0.0)
                    val lastUpdated = obj.optString("lastUpdated", "Live")

                    views.setTextViewText(R.id.tv_total_bank_cash, formatInr(totalBankCash))
                    views.setTextViewText(R.id.tv_total_credit_avail, formatInr(totalCreditAvail))
                    views.setTextViewText(R.id.tv_total_credit_limit, "Limit: " + formatInr(totalCreditLimit))
                    views.setTextViewText(R.id.tv_last_updated, "Synced " + lastUpdated)

                    // Banks list (up to 4)
                    val banks = obj.optJSONArray("banks")
                    val bankRowIds = intArrayOf(R.id.row_bank_1, R.id.row_bank_2, R.id.row_bank_3, R.id.row_bank_4)
                    val bankNameIds = intArrayOf(R.id.tv_bank_1_name, R.id.tv_bank_2_name, R.id.tv_bank_3_name, R.id.tv_bank_4_name)
                    val bankValIds = intArrayOf(R.id.tv_bank_1_val, R.id.tv_bank_2_val, R.id.tv_bank_3_val, R.id.tv_bank_4_val)

                    bankCount = banks?.length() ?: 0
                    for (i in 0 until 4) {
                        if (i < bankCount) {
                            val item = banks!!.getJSONObject(i)
                            views.setViewVisibility(bankRowIds[i], View.VISIBLE)
                            views.setTextViewText(bankNameIds[i], item.optString("name", "Bank"))
                            views.setTextViewText(bankValIds[i], formatInr(item.optDouble("balance", 0.0)))
                        } else {
                            views.setViewVisibility(bankRowIds[i], View.GONE)
                        }
                    }

                    // Cash in Hand
                    if (totalCash > 0) {
                        views.setViewVisibility(R.id.row_cash, View.VISIBLE)
                        views.setTextViewText(R.id.tv_cash_val, formatInr(totalCash))
                    } else {
                        views.setViewVisibility(R.id.row_cash, View.GONE)
                    }

                    // Credit Cards list (up to 4)
                    val cards = obj.optJSONArray("cards")
                    val cardRowIds = intArrayOf(R.id.row_card_1, R.id.row_card_2, R.id.row_card_3, R.id.row_card_4)
                    val cardNameIds = intArrayOf(R.id.tv_card_1_name, R.id.tv_card_2_name, R.id.tv_card_3_name, R.id.tv_card_4_name)
                    val cardAvailIds = intArrayOf(R.id.tv_card_1_avail, R.id.tv_card_2_avail, R.id.tv_card_3_avail, R.id.tv_card_4_avail)

                    cardCount = cards?.length() ?: 0
                    for (i in 0 until 4) {
                        if (i < cardCount) {
                            val item = cards!!.getJSONObject(i)
                            views.setViewVisibility(cardRowIds[i], View.VISIBLE)
                            views.setTextViewText(cardNameIds[i], item.optString("name", "Card"))
                            views.setTextViewText(cardAvailIds[i], formatInr(item.optDouble("avail", 0.0)))
                        } else {
                            views.setViewVisibility(cardRowIds[i], View.GONE)
                        }
                    }

                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }

            // Visibility for empty state vs content
            if (bankCount == 0 && cardCount == 0 && totalCash == 0.0) {
                views.setViewVisibility(R.id.balances_content, View.GONE)
                views.setViewVisibility(R.id.tv_empty_state, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.balances_content, View.VISIBLE)
                views.setViewVisibility(R.id.tv_empty_state, View.GONE)
            }

            // Tap anywhere on widget -> Open Account Balances Screen
            val openIntent = Intent(context, MainActivity::class.java).apply {
                action = "action_view_balances"
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val openPending = PendingIntent.getActivity(
                context, 100, openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_container, openPending)

            // Tap Refresh button -> Trigger sync
            val refreshIntent = Intent(context, MainActivity::class.java).apply {
                action = "action_refresh_widget"
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val refreshPending = PendingIntent.getActivity(
                context, 101, refreshIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.btn_refresh, refreshPending)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
