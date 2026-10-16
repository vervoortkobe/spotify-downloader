package com.scooby.spotterfy

import android.content.ComponentName
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Bundle
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.session.MediaControllerCompat
import androidx.car.app.CarAppService
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.car.app.validation.HostValidator
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver

/** Android Auto entry point. Browsing and playback use audio_service's media session. */
class SpotterfyCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator {
        // Allow any host in debug so the Android Auto emulator and local test
        // hosts can connect. Release builds accept only known car hosts.
        return if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            HostValidator.Builder(this)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }
    }

    override fun onCreateSession(): Session = SpotterfyCarSession()
}

class SpotterfyCarSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen = SpotterfyBrowseScreen(carContext)
}

private class SpotterfyBrowseScreen(
    carContext: CarContext,
    private val parentId: String = "root",
    private val screenTitle: String = "Spotterfy",
) : Screen(carContext) {
    private var controller: MediaControllerCompat? = null
    private var currentParent = parentId
    private var title = screenTitle
    private var items: List<MediaBrowserCompat.MediaItem> = emptyList()
    private var loading = true
    private var error: String? = null
    private lateinit var browser: MediaBrowserCompat

    init {
        browser = MediaBrowserCompat(
            carContext,
            ComponentName(carContext, "com.ryanheise.audioservice.AudioService"),
            object : MediaBrowserCompat.ConnectionCallback() {
                override fun onConnected() {
                    controller = MediaControllerCompat(carContext, browser.sessionToken)
                    loadChildren(currentParent)
                }

                override fun onConnectionFailed() {
                    error = "Unable to connect to Spotterfy playback"
                    invalidate()
                }
            },
            null,
        )
        lifecycle.addObserver(
            LifecycleEventObserver { _, event ->
                if (event == Lifecycle.Event.ON_DESTROY) {
                    try {
                        browser.unsubscribe(currentParent)
                        browser.disconnect()
                    } catch (_: Exception) {
                    }
                }
            },
        )
        browser.connect()
    }

    private fun loadChildren(parentId: String) {
        currentParent = parentId
        loading = true
        error = null
        invalidate()
        browser.subscribe(parentId, object : MediaBrowserCompat.SubscriptionCallback() {
            override fun onChildrenLoaded(
                parentId: String,
                children: List<MediaBrowserCompat.MediaItem>,
            ) {
                if (parentId != currentParent) return
                items = children
                loading = false
                invalidate()
            }

            override fun onError(parentId: String) {
                if (parentId != currentParent) return
                items = emptyList()
                loading = false
                error = "Could not load this library"
                invalidate()
            }
        })
    }

    override fun onGetTemplate(): Template {
        val list = ItemList.Builder()
        if (loading) list.setNoItemsMessage("Loading Spotterfy...")
        else if (items.isEmpty()) list.setNoItemsMessage(error ?: "No music available")
        else items.forEach { item ->
            val description = item.description
            val row = Row.Builder()
                .setTitle(description.title ?: "Unknown")
                .apply {
                    description.subtitle?.let { addText(it) }
                    description.description?.let { addText(it) }
                }
                .setBrowsable(item.isBrowsable)
                .setOnClickListener {
                    val mediaId = item.mediaId ?: return@setOnClickListener
                    if (item.isBrowsable) {
                        screenManager.push(
                            SpotterfyBrowseScreen(
                                carContext,
                                mediaId,
                                description.title?.toString() ?: "Spotterfy",
                            ),
                        )
                    } else if (item.isPlayable) {
                        controller?.transportControls?.playFromMediaId(mediaId, Bundle())
                    }
                }
                .build()
            list.addItem(row)
        }

        return ListTemplate.Builder()
            .setTitle(title)
            .setHeaderAction(if (currentParent == "root") Action.APP_ICON else Action.BACK)
            .setLoading(loading)
            .setSingleList(list.build())
            .build()
    }

}
