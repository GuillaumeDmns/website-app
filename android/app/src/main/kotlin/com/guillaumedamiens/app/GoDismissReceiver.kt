package com.guillaumedamiens.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * GO's notification swiped away: the journey is still followed (its service runs, the alerts still ring), its
 * notification stays away until the app is on screen again ([MainActivity.onResume]) or another journey starts.
 */
class GoDismissReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        LiveJourneyNotification.dismissedByUser = true
    }
}
