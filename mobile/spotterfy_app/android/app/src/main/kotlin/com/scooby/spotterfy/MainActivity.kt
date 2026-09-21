package com.scooby.spotterfy

import com.ryanheise.audioservice.AudioServiceActivity

// Must extend AudioServiceActivity (not FlutterActivity/FlutterFragmentActivity)
// so AudioServicePlugin can link to the shared FlutterEngine. See
// https://pub.dev/packages/audio_service#custom-android-activity
class MainActivity : AudioServiceActivity()
