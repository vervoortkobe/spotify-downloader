package com.scooby.spotterfy

import android.media.MediaScannerConnection
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Must extend AudioServiceActivity (not FlutterActivity/FlutterFragmentActivity)
// so AudioServicePlugin can link to the shared FlutterEngine. See
// https://pub.dev/packages/audio_service#custom-android-activity
class MainActivity : AudioServiceActivity() {

    private val CHANNEL = "com.scooby.spotterfy/media_store"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Downloads live in public storage (/storage/emulated/0/Spotterfy/Music)
        // so other music apps can see them. Writing the file is not enough for
        // that: MediaStore only knows about it once it has been scanned, so every
        // new download is announced here and every deleted one is removed from
        // the index.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanFile" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("bad_args", "path is required", null)
                        } else {
                            // mimeType must be set or some players file the
                            // track under "unknown" and refuse to play it.
                            MediaScannerConnection.scanFile(
                                applicationContext,
                                arrayOf(path),
                                arrayOf("audio/mpeg"),
                                null,
                            )
                            result.success(true)
                        }
                    }

                    "deleteScan" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("bad_args", "path is required", null)
                        } else {
                            // Removes the MediaStore row for the deleted file;
                            // without this the track lingers in other players
                            // and tapping it opens a missing file.
                            MediaScannerConnection.scanFile(
                                applicationContext,
                                arrayOf(path),
                                null,
                            ) { _, uri ->
                                if (uri != null) {
                                    applicationContext.contentResolver.delete(uri, null, null)
                                }
                                result.success(true)
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
