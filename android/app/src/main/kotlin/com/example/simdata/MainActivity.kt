package com.example.simdata

import android.app.role.RoleManager
import android.content.Intent
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

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        val prefs = getSharedPreferences("cfg", MODE_PRIVATE)
        MethodChannel(engine.dartExecutor.binaryMessenger, "sim_channel")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSims" -> try {
                        val sm = getSystemService(SubscriptionManager::class.java)
                        val dataId = SubscriptionManager.getDefaultDataSubscriptionId()
                        result.success((sm.activeSubscriptionInfoList ?: emptyList()).map {
                            mapOf(
                                "subId" to it.subscriptionId,
                                "slot" to it.simSlotIndex,
                                "carrier" to it.carrierName.toString(),
                                "number" to numberOf(sm, it.subscriptionId),
                                "isData" to (it.subscriptionId == dataId),
                                "dataEnabled" to dataEnabledOf(it.subscriptionId),
                                "roaming" to sm.isNetworkRoaming(it.subscriptionId)
                            )
                        })
                    } catch (e: SecurityException) {
                        result.error("PERMISSION", e.message, null)
                    }
                    "getConfig" -> {
                        val arr = JSONArray(prefs.getString("log", "[]"))
                        val log = (arr.length() - 1 downTo 0).map {
                            val o = arr.getJSONObject(it)
                            mapOf("number" to o.optString("number"), "time" to o.optLong("time"),
                                  "action" to o.optString("action"))
                        }
                        result.success(mapOf(
                            "blocked" to prefs.getInt("blocked", -1),
                            "mode" to (prefs.getString("mode", "reject") ?: "reject"),
                            "enabled" to prefs.getBoolean("enabled", true),
                            "allowContacts" to prefs.getBoolean("allowContacts", false),
                            "notify" to prefs.getBoolean("notify", false),
                            "total" to prefs.getLong("total", 0L),
                            "allowed" to (prefs.getStringSet("allowed", emptySet())!!.toList()),
                            "log" to log
                        ))
                    }
                    "setConfig" -> {
                        val m = call.arguments as Map<*, *>
                        val e = prefs.edit()
                        (m["blocked"] as? Int)?.let { e.putInt("blocked", it) }
                        (m["mode"] as? String)?.let { e.putString("mode", it) }
                        (m["enabled"] as? Boolean)?.let { e.putBoolean("enabled", it) }
                        (m["allowContacts"] as? Boolean)?.let { e.putBoolean("allowContacts", it) }
                        (m["notify"] as? Boolean)?.let { e.putBoolean("notify", it) }
                        (m["allowed"] as? List<*>)?.let { l ->
                            e.putStringSet("allowed", l.map { it.toString() }.toSet())
                        }
                        if (m["clearLog"] == true) e.putString("log", "[]").putLong("total", 0L)
                        e.apply()
                        result.success(null)
                    }
                    "hasScreeningRole" -> {
                        val rm = getSystemService(RoleManager::class.java)
                        result.success(rm.isRoleAvailable(RoleManager.ROLE_CALL_SCREENING) &&
                            rm.isRoleHeld(RoleManager.ROLE_CALL_SCREENING))
                    }
                    "requestScreeningRole" -> {
                        val rm = getSystemService(RoleManager::class.java)
                        if (rm.isRoleAvailable(RoleManager.ROLE_CALL_SCREENING) &&
                            !rm.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)) {
                            startActivityForResult(
                                rm.createRequestRoleIntent(RoleManager.ROLE_CALL_SCREENING), 100)
                        }
                        result.success(null)
                    }
                    "openDataSettings" -> {
                        startActivity(Intent(Settings.ACTION_NETWORK_OPERATOR_SETTINGS))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
