package com.beamdrop.receiver.service

import android.app.Notification
import android.content.Intent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.beamdrop.receiver.model.MirroredNotification

class BeamDropNotificationListenerService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        val pkg = sbn.packageName ?: return
        // Don't mirror our own notifications or system download manager
        if (pkg == packageName || pkg == "android") return

        val notification = sbn.notification ?: return

        // Skip ongoing persistent foreground notifications unless they have content
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

        val mirrored = MirroredNotification(
            id = "${sbn.id}_${sbn.postTime}",
            packageName = pkg,
            appName = appName,
            title = title,
            text = text,
            timestamp = sbn.postTime
        )

        Log.i(TAG, "Notification intercepted: [$appName] $title: $text")
        onNotificationReceivedListener?.invoke(mirrored)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
    }

    companion object {
        private const val TAG = "NotificationListener"
        var onNotificationReceivedListener: ((MirroredNotification) -> Unit)? = null
    }
}
