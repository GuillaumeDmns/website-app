package com.guillaumedamiens.app

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.core.net.toUri

/**
 * The quick settings tile "Rentrer" (added by the user from the panel's editor): the journeys home from here, in one
 * tap from anywhere, the lock screen included (after unlocking). It opens [MainActivity] with the link of the home
 * shortcut ([AppShortcuts.homeLink], kept as the saved places change); without a saved home, the app itself, and the
 * tile says what is missing. Never shown as "on": it starts something, it is no setting.
 */
class HomeTileService : TileService() {

    override fun onStartListening() {
        val tile = qsTile ?: return
        tile.state = Tile.STATE_INACTIVE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = if (AppShortcuts.homeLink(this) == null) getString(R.string.home_tile_no_home) else null
        }
        tile.updateTile()
    }

    override fun onClick() {
        if (isLocked) {
            unlockAndRun(::open)
        } else {
            open()
        }
    }

    private fun open() {
        val link = AppShortcuts.homeLink(this)
        val intent = (if (link != null) Intent(Intent.ACTION_VIEW, link.toUri(), this, MainActivity::class.java)
        else Intent(this, MainActivity::class.java))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                // Android 14 only takes a PendingIntent here
                startActivityAndCollapse(
                    PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                )
            } else {
                @Suppress("DEPRECATION", "StartActivityAndCollapseDeprecated")
                startActivityAndCollapse(intent)
            }
        } catch (e: Exception) {
            // The panel gone meanwhile: nothing to open from
        }
    }
}
