package com.beamdrop.receiver.service

import android.app.Notification
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.telephony.SmsManager
import android.util.Log
import com.beamdrop.receiver.model.MirroredNotification
import java.util.concurrent.ConcurrentHashMap

class BeamDropNotificationListenerService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        val pkg = sbn.packageName ?: return
        if (pkg == packageName || pkg == "android") return

        val notification = sbn.notification ?: return

        val category = notification.category
        val isCall = (category == Notification.CATEGORY_CALL) ||
                     (category == Notification.CATEGORY_MISSED_CALL) ||
                     pkg in listOf(
                         "com.google.android.dialer",
                         "com.samsung.android.incallui",
                         "com.android.phone",
                         "com.android.server.telecom",
                         "com.whatsapp",
                         "com.truecaller"
                     )

        val isOngoing = (notification.flags and Notification.FLAG_ONGOING_EVENT) != 0
        if (isOngoing && !isCall) return

        val extras = notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
            ?: extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""

        if (title.isEmpty() && text.isEmpty()) return

        val appName = try {
            val appInfo = packageManager.getApplicationInfo(pkg, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        } catch (_: Exception) {
            pkg
        }

        // Extract potential phone number
        var phoneNumber: String? = null
        if (isCall) {
            val phoneExtra = extras.getString("android.phone")
                ?: extras.getString("android.phoneNumber")
                ?: extras.getString("android.title")
            if (!phoneExtra.isNullOrEmpty() && phoneExtra.matches(Regex("^[+0-9\\s\\-()]{5,}$"))) {
                phoneNumber = phoneExtra.replace(" ", "")
            } else if (title.matches(Regex("^[+0-9\\s\\-()]{5,}$"))) {
                phoneNumber = title.replace(" ", "")
            }
        }

        // Check for actions & quick reply RemoteInput action
        var canReply = false
        val actions = notification.actions
        if (actions != null) {
            notificationActions[sbn.key] = actions
            for (action in actions) {
                val remoteInputs = action.remoteInputs
                if (remoteInputs != null && remoteInputs.isNotEmpty()) {
                    replyActions[sbn.key] = Pair(action, remoteInputs[0])
                    canReply = true
                    break
                }
            }
        }

        if (isCall) {
            latestCallKey = sbn.key
        }

        val mirrored = MirroredNotification(
            id = "${sbn.id}_${sbn.postTime}",
            packageName = pkg,
            appName = if (isCall) "📞 Incoming Call" else appName,
            title = title,
            text = text,
            timestamp = sbn.postTime,
            key = sbn.key,
            canReply = canReply,
            isCall = isCall,
            phoneNumber = phoneNumber
        )

        Log.i(TAG, "Notification intercepted: [$appName] $title: $text (canReply=$canReply, isCall=$isCall, phone=$phoneNumber)")
        onNotificationReceivedListener?.invoke(mirrored)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        sbn?.key?.let {
            replyActions.remove(it)
            notificationActions.remove(it)
            if (latestCallKey == it) latestCallKey = null
        }
    }

    companion object {
        private const val TAG = "NotificationListener"
        var onNotificationReceivedListener: ((MirroredNotification) -> Unit)? = null
        private val replyActions = ConcurrentHashMap<String, Pair<Notification.Action, RemoteInput>>()
        private val notificationActions = ConcurrentHashMap<String, Array<Notification.Action>>()
        @Volatile var latestCallKey: String? = null

        fun declineCall(context: Context, key: String? = null): Boolean {
            val targetKey = key ?: latestCallKey ?: return false
            val actions = notificationActions[targetKey] ?: return false

            for (action in actions) {
                val title = action.title?.toString()?.lowercase() ?: ""
                if (title.contains("decline") || title.contains("reject") ||
                    title.contains("dismiss") || title.contains("hang") ||
                    title.contains("end call")) {
                    return try {
                        action.actionIntent.send(context, 0, Intent())
                        Log.i(TAG, "Successfully triggered decline action on $targetKey ($title)")
                        true
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to invoke decline action: ${e.message}")
                        false
                    }
                }
            }
            // Fallback: trigger first action if only decline/hang up exists
            if (actions.isNotEmpty()) {
                return try {
                    actions[0].actionIntent.send(context, 0, Intent())
                    true
                } catch (_: Exception) { false }
            }
            return false
        }

        fun sendQuickReplyOrSms(context: Context, key: String, phoneNumber: String?, message: String): Boolean {
            // First try inline notification reply
            if (sendReply(context, key, message)) {
                return true
            }
            // If phone number is available, attempt SMS send
            if (!phoneNumber.isNullOrBlank()) {
                return try {
                    val smsManager = context.getSystemService(SmsManager::class.java) ?: SmsManager.getDefault()
                    smsManager.sendTextMessage(phoneNumber, null, message, null, null)
                    Log.i(TAG, "Sent SMS to $phoneNumber: $message")
                    true
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to send SMS: ${e.message}")
                    false
                }
            }
            return false
        }

        fun muteRinger(context: Context): Boolean {
            return try {
                val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                am?.adjustVolume(AudioManager.ADJUST_MUTE, 0)
                Log.i(TAG, "Ringer muted successfully")
                true
            } catch (e: Exception) {
                Log.e(TAG, "Failed to mute ringer: ${e.message}")
                false
            }
        }

        fun sendReply(context: Context, key: String, replyText: String): Boolean {
            val pair = replyActions[key] ?: return false
            val action = pair.first
            val remoteInput = pair.second

            val intent = Intent()
            val bundle = Bundle().apply {
                putCharSequence(remoteInput.resultKey, replyText)
            }
            RemoteInput.addResultsToIntent(arrayOf(remoteInput), intent, bundle)

            return try {
                action.actionIntent.send(context, 0, intent)
                Log.i(TAG, "Successfully dispatched reply to $key: $replyText")
                true
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send notification reply: ${e.message}")
                false
            }
        }
    }
}
