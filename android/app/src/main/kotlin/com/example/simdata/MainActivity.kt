package com.example.simdata

import android.app.role.RoleManager
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.provider.Settings
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

class MainActivity : FlutterActivity() {

    private fun numberOf(sm: SubscriptionManager, id: Int): String = try {
        if (Build.VERSION.SDK_INT >= 33) sm.getPhoneNumber(id)
        else getSystemService(TelephonyManager::class.java)
            .createForSubscriptionId(id).line1Number ?: ""
    } catch (e: Throwable) { "" }

    private fun dataEnabledOf(id: Int): Boolean = try {
        getSystemService(TelephonyManager::class.java)
            .createForSubscriptionId(id).isDataEnabled
    } catch (e: Throwable) { false }

    private fun roamingOf(sm: SubscriptionManager, id: Int): Boolean = try {
        sm.isNetworkRoaming(id)
    } catch (e: Throwable) { false }

    private fun simsList(): List<Map<String, Any>> {
        val sm = getSystemService(SubscriptionManager::class.java)
        val dataId = SubscriptionManager.getDefaultDataSubscriptionId()
        return (sm.activeSubscriptionInfoList ?: emptyList()).map {
            mapOf<String, Any>(
                "subId" to it.subscriptionId,
                "slot" to it.simSlotIndex,
                "carrier" to (it.carrierName?.toString() ?: ""),
                "number" to numberOf(sm, it.subscriptionId),
                "isData" to (it.subscriptionId == dataId),
                "dataEnabled" to dataEnabledOf(it.subscriptionId),
                "roaming" to roamingOf(sm, it.subscriptionId)
            )
        }
    }

    private fun readLog(prefs: SharedPreferences): List<Map<String, Any>> = try {
        val arr = JSONArray(prefs.getString("log", "[]") ?: "[]")
        (arr.length() - 1 downTo 0).map { i ->
            val o = arr.getJSONObject(i)
            mapOf<String, Any>(
                "number" to o.optString("number"),
                "time" to o.optLong("time"),
                "action" to o.optString("action")
            )
        }
    } catch (e: Throwable) { emptyList() }

    private fun readConfig(prefs: SharedPreferences): Map<String, Any> = mapOf(
        "blocked" to prefs.getInt("blocked", -1),
        "mode" to (prefs.getString("mode", "reject") ?: "reject"),
        "enabled" to prefs.getBoolean("enabled", true),
        "allowContacts" to prefs.getBoolean("allowContacts", false),
        "notify" to prefs.getBoolean("notify", false),
        "total" to prefs.getLong("total", 0L),
        "allowed" to (prefs.getStringSet("allowed", emptySet()) ?: emptySet()).toList(),
        "log" to readLog(prefs)
    )

    private fun writeConfig(prefs: SharedPreferences, m: Map<*, *>) {
        val e = prefs.edit()
        (m["blocked"] as? Number)?.let { e.putInt("blocked", it.toInt()) }
        (m["mode"] as? String)?.let { e.putString("mode", it) }
        (m["enabled"] as? Boolean)?.let { e.putBoolean("enabled", it) }
        (m["allowContacts"] as? Boolean)?.let { e.putBoolean("allowContacts", it) }
        (m["notify"] as? Boolean)?.let { e.putBoolean("notify", it) }
        (m["allowed"] as? List<*>)?.let { l ->
            e.putStringSet("allowed", l.map { it.toString() }.toSet())
        }
        if (m["clearLog"] == true) e.putString("log", "[]").putLong("total", 0L)
        // commit (متزامن) حتى تراه خدمة الحظر فوراً
        e.commit()
    }

    private fun openDataSettings() {
        try {
            startActivity(Intent(Settings.ACTION_NETWORK_OPERATOR_SETTINGS))
        } catch (e: Throwable) {
            startActivity(Intent(Settings.ACTION_SETTINGS))
        }
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        val prefs = getSharedPreferences("cfg", MODE_PRIVATE)
        MethodChannel(engine.dartExecutor.binaryMessenger, "sim_channel")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "getSims" -> result.success(simsList())
                        "getConfig" -> result.success(readConfig(prefs))
                        "setConfig" -> {
                            writeConfig(prefs, call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())
                            result.success(null)
                        }
                        "hasScreeningRole" -> {
                            val rm = getSystemService(RoleManager::class.java)
                            result.success(rm != null &&
                                rm.isRoleAvailable(RoleManager.ROLE_CALL_SCREENING) &&
                                rm.isRoleHeld(RoleManager.ROLE_CALL_SCREENING))
                        }
                        "requestScreeningRole" -> {
                            val rm = getSystemService(RoleManager::class.java)
                            if (rm != null &&
                                rm.isRoleAvailable(RoleManager.ROLE_CALL_SCREENING) &&
                                !rm.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)) {
                                startActivityForResult(
                                    rm.createRequestRoleIntent(RoleManager.ROLE_CALL_SCREENING), 100)
                            }
                            result.success(null)
                        }
                        "openDataSettings" -> {
                            openDataSettings()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: SecurityException) {
                    result.error("PERMISSION", e.message, null)
                } catch (e: Throwable) {
                    result.error("ERROR", e.message ?: e.javaClass.simpleName, null)
                }
            }
    }
}
