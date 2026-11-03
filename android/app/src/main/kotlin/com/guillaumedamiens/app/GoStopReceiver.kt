package com.guillaumedamiens.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.edit

/**
 * "Terminer" in GO's notification: the notification and the service go at once, and the app ends the session
 * ([MainActivity.bridge], `stopRequested`); without its engine running, it does at its next start (`takeStopRequest`).
 */
class GoStopReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        GoService.stop(context)
        LiveJourneyNotification.cancelJourney(context)
        val bridge = MainActivity.bridge
        if (bridge != null) {
            bridge.invokeMethod("stopRequested", null)
        } else {
            preferences(context).edit { putBoolean(KEY, true) }
        }
    }

    companion object {
        private const val PREFERENCES = "go_stop"
        private const val KEY = "requested"

        private fun preferences(context: Context) = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

        /** Whether "Terminer" was tapped while the app wasn't running, forgotten once asked */
        fun take(context: Context): Boolean {
            val requested = preferences(context).getBoolean(KEY, false)
            if (requested) {
                preferences(context).edit { remove(KEY) }
            }
            return requested
        }
    }
}
