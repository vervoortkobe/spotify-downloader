import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/track_model.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  FlutterLocalNotificationsPlugin? _plugin;
  bool _initialized = false;

  void Function()? onPlayPause;
  void Function()? onNext;
  void Function()? onPrevious;
  void Function()? onClose;
  void Function()? onNotificationTap;

  Future<void> initialize() async {
    if (_initialized) return;
    _plugin = FlutterLocalNotificationsPlugin();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin!.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin!.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      
      // Create playback channel with high importance for Samsung Now Bar compatibility
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          'playback_channel',
          'Playback',
          description: 'Music playback controls',
          importance: Importance.max,
          playSound: false,
          enableVibration: false,
          showBadge: false,
        ),
      );
    }

    _initialized = true;
  }

  void _onNotificationResponse(NotificationResponse response) {
    switch (response.actionId) {
      case 'android.intent.action.MEDIA_PLAY_PAUSE':
        onPlayPause?.call();
        break;
      case 'android.intent.action.MEDIA_NEXT':
        onNext?.call();
        break;
      case 'android.intent.action.MEDIA_PREVIOUS':
        onPrevious?.call();
        break;
      case 'android.intent.action.MEDIA_STOP':
        onClose?.call();
        break;
      default:
        onNotificationTap?.call();
        break;
    }
  }

  static String _posText(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> showPlaybackNotification({
    required TrackModel track,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  }) async {
    if (!_initialized || _plugin == null) return;

    final sub = '${track.artists}  •  ${_posText(position)} / ${_posText(duration)}';

    final androidDetails = AndroidNotificationDetails(
      'playback_channel',
      'Playback',
      channelDescription: 'Music playback controls',
      importance: Importance.max,
      priority: Priority.max,
      ongoing: true,
      showWhen: false,
      usesChronometer: true,
      chronometerCountDown: false,
      playSound: false,
      enableVibration: false,
      visibility: NotificationVisibility.public,
      // Make notification expandable to full height and sticky
      ticker: 'Now Playing: ${track.title}',
      autoCancel: false,
      onlyAlertOnce: true,
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'android.intent.action.MEDIA_PREVIOUS',
          'Previous',
          showsUserInterface: true,
          icon: DrawableResourceAndroidBitmap('ic_media_previous'),
        ),
        AndroidNotificationAction(
          'android.intent.action.MEDIA_PLAY_PAUSE',
          isPlaying ? 'Pause' : 'Play',
          showsUserInterface: true,
          icon: DrawableResourceAndroidBitmap(
            isPlaying ? 'ic_media_pause' : 'ic_media_play'
          ),
        ),
        const AndroidNotificationAction(
          'android.intent.action.MEDIA_NEXT',
          'Next',
          showsUserInterface: true,
          icon: DrawableResourceAndroidBitmap('ic_media_next'),
        ),
        const AndroidNotificationAction(
          'android.intent.action.MEDIA_STOP',
          'Close',
          showsUserInterface: true,
          icon: DrawableResourceAndroidBitmap('ic_media_close'),
        ),
      ],
      // Use MediaStyleInformation for Samsung Now Bar compatibility
      styleInformation: MediaStyleInformation(
        htmlFormatContent: true,
        htmlFormatTitle: true,
      ),
    );

    await _plugin!.show(
      id: 0,
      title: track.title,
      body: sub,
      notificationDetails: NotificationDetails(android: androidDetails),
    );
  }

  Future<void> cancelPlaybackNotification() async {
    if (_plugin != null) {
      await _plugin!.cancel(id: 0);
    }
  }
}
