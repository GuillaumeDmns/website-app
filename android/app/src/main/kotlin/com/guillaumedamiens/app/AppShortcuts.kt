package com.guillaumedamiens.app

import android.content.Context
import android.content.Intent
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import androidx.core.net.toUri

/**
 * The launcher's shortcuts (a long press on the app's icon; each can be dragged to the home screen): the saved places
 * the Dart side gives (home, work: the journeys to them from here), then the traffic. Each opens [MainActivity] with
 * a `guillaumedamiens://app/<page>?launch=1` link: Flutter gives its path and query to the app's router, which opens
 * that page over the home page (`launchLink`, `router.dart`). Dynamic ones: the
 * app's id differs per flavor, which a shortcuts XML can't follow.
 */
object AppShortcuts {

    /** @param places `id`, `label` and `uri` of each saved place, in order */
    fun set(context: Context, places: List<Map<String, String>>) {
        val shortcuts = places.mapNotNull { place ->
            val id = place["id"] ?: return@mapNotNull null
            val label = place["label"]?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
            val uri = place["uri"] ?: return@mapNotNull null
            shortcut(context, "place_$id", label, uri, R.drawable.ic_near_me)
        } + shortcut(context, "traffic", context.getString(R.string.shortcut_traffic), "guillaumedamiens://app/traffic?launch=1", R.drawable.ic_train)
        try {
            ShortcutManagerCompat.setDynamicShortcuts(context, shortcuts.take(ShortcutManagerCompat.getMaxShortcutCountPerActivity(context)))
        } catch (e: Exception) {
            // A launcher without shortcuts, or too many changes at once: the ones before stay
        }
    }

    private fun shortcut(context: Context, id: String, label: String, uri: String, icon: Int) =
        ShortcutInfoCompat.Builder(context, id)
            .setShortLabel(label)
            .setIcon(IconCompat.createWithResource(context, icon))
            .setIntent(Intent(Intent.ACTION_VIEW, uri.toUri(), context, MainActivity::class.java))
            .build()
}
