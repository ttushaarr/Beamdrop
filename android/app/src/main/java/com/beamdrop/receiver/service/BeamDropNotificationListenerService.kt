package com.beamdrop.receiver.service

import android.app.Notification
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
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

        val isOngoing = (notification.flags and Notification.FLAG_ONGOING_EVENT) != 0
        if (isOngoing) return

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

        // Check for quick reply RemoteInput action
        var canReply = false
        val actions = notification.actions
        if (actions != null) {
            for (action in actions) {
                val remoteInputs = action.remoteInputs
                if (remoteInputs != null && remoteInputs.isNotEmpty()) {
                    replyActions[sbn.key] = Pair(action, remoteInputs[0])
                    canReply = true
                    break
                }
            }
        }

        val mirrored = MirroredNotification(
            id = "${sbn.id}_${sbn.postTime}",
            packageName = pkg,
            appName = appName,
            title = title,
            text = text,
            timestamp = sbn.postTime,
            key = sbn.key,
            canReply = canReply
        )

        Log.i(TAG, "Notification intercepted: [$appName] $title: $text (canReply=$canReply)")
        onNotificationReceivedListener?.invoke(mirrored)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        sbn?.key?.let { replyActions.remove(it) }
    }

    companion object {
        private const val TAG = "NotificationListener"
        var onNotificationReceivedListener: ((MirroredNotification) -> Unit)? = null
        private val replyActions = ConcurrentHashMap<String, Pair<Notification.Action, RemoteInput>>()

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
