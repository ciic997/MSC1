package com.example.simdata

import android.Manifest
import android.app.NotificationChannel
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.ContactsContract
import android.telecom.Call
import android.telecom.CallScreeningService
import android.telecom.PhoneAccountHandle
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import org.json.JSONArray
import org.json.JSONObject

class BlockCallService : CallScreeningService() {

    companion object {
        const val CHANNEL_ID = "blocked_calls"
        const val MAX_LOG = 100
    }

    /** يحوّل أي رقم (بما فيه الأرقام العربية) إلى أرقام 0-9 فقط. */
    private fun digits(s: String) = buildString {
        for (c in s) {
            val d = Character.digit(c, 10)
            if (d >= 0) append(d)
        }
    }

    private fun sameNumber(a: String, b: String): Boolean {
        val x = digits(a)
        val y = digits(b)
        if (x.length < 6 || y.length < 6) return false
        val k = minOf(8, x.length, y.length)
        return x.takeLast(k) == y.takeLast(k)
    }

    /** يحدد معرّف الاشتراك (subId) للشريحة التي وصلت عليها المكالمة. */
    private fun subIdOf(h: PhoneAccountHandle): Int {
        try {
            if (Build.VERSION.SDK_INT >= 30) {
                val tm = getSystemService(TelephonyManager::class.java)
                    .createForPhoneAccountHandle(h)
                val id = tm?.subscriptionId ?: -1
                if (id != -1) return id
            }
        } catch (_: Throwable) {}
        try {
            val sm = getSystemService(SubscriptionManager::class.java)
            sm.activeSubscriptionInfoList?.firstOrNull { it.iccId == h.id }
                ?.let { return it.subscriptionId }
        } catch (_: Throwable) {}
        return h.id?.toIntOrNull() ?: -1
    }

    private fun isContact(number: String): Boolean {
        if (number.isEmpty()) return false
        if (checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) return false
        return try {
            val uri = Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number))
            contentResolver.query(uri, arrayOf(ContactsContract.PhoneLookup._ID), null, null, null)
                ?.use { it.count > 0 } ?: false
        } catch (_: Throwable) { false }
    }

    override fun onScreenCall(details: Call.Details) {
        val prefs = getSharedPreferences("cfg", MODE_PRIVATE)
        val blocked = prefs.getInt("blocked", -1)
        val enabled = prefs.getBoolean("enabled", true)
        val resp = CallResponse.Builder()

        try {
            if (enabled && blocked != -1 &&
                details.callDirection == Call.Details.DIRECTION_INCOMING) {

                val h = details.accountHandle
                val subId = if (h != null) subIdOf(h) else -1

                if (subId == blocked) {
                    val number = details.handle?.schemeSpecificPart ?: ""
                    val allowed = prefs.getStringSet("allowed", emptySet()) ?: emptySet()
                    val isAllowed = allowed.any { sameNumber(it, number) } ||
                        (prefs.getBoolean("allowContacts", false) && isContact(number))

                    if (!isAllowed) {
                        val silence = prefs.getString("mode", "reject") == "silence"
                        if (silence) resp.setSilenceCall(true)
                        else resp.setDisallowCall(true).setRejectCall(true).setSkipNotification(true)
                        append(prefs, number, if (silence) "silence" else "reject")
                        if (prefs.getBoolean("notify", false)) notifyBlocked(number, silence)
                    }
                }
            }
        } catch (_: Throwable) {
            // أي خطأ → نسمح للمكالمة بدل أن نخسر مكالمة مهمة
        }
        respondToCall(details, resp.build())
    }

    private fun notifyBlocked(number: String, silence: Boolean) {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "المكالمات المحجوبة", NotificationManager.IMPORTANCE_LOW))
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pi = PendingIntent.getActivity(this, 0, launch, PendingIntent.FLAG_IMMUTABLE)
        val n = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_call_missed)
            .setContentTitle(if (silence) "تم كتم مكالمة" else "تم رفض مكالمة")
            .setContentText(if (number.isEmpty()) "رقم مخفي" else number)
            .setContentIntent(pi)
            .setAutoCancel(true)
            .build()
        nm.notify((System.currentTimeMillis() % Int.MAX_VALUE).toInt(), n)
    }

    @Synchronized
    private fun append(prefs: SharedPreferences, number: String, action: String) {
        val old = JSONArray(prefs.getString("log", "[]"))
        val arr = JSONArray()
        val start = maxOf(0, old.length() - (MAX_LOG - 1))
        for (i in start until old.length()) arr.put(old.get(i))
        arr.put(JSONObject().put("number", number)
            .put("time", System.currentTimeMillis()).put("action", action))
        prefs.edit()
            .putString("log", arr.toString())
            .putLong("total", prefs.getLong("total", 0L) + 1)
            .apply()
    }
}
