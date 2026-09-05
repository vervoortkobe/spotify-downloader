import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
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
      try {
        await android?.requestNotificationsPermission();
      } catch (e) {
        debugPrint('[NotificationService] requestNotificationsPermission failed (Activity not ready): $e');
      }
      try {
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
      } catch (e) {
        debugPrint('[NotificationService] createNotificationChannel failed: $e');
      }
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

    final isLong = duration.inSeconds > 0;
    final prog = isLong ? position.inSeconds.clamp(0, duration.inSeconds) : 0;
    final maxProg = isLong ? duration.inSeconds : 100;

    final androidDetails = AndroidNotificationDetails(
      'playback_channel',
      'Playback',
      channelDescription: 'Music playback controls — Now Bar',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: isPlaying,
      autoCancel: false,
      onlyAlertOnce: true,
      showWhen: false,
      playSound: false,
      enableVibration: false,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.transport,
      ticker: 'Now Playing: ${track.title}',
      color: const Color(0xFF10b981),
      colorized: true,
      largeIcon: track.cover.isNotEmpty ? null : const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      showProgress: isLong,
      maxProgress: maxProg,
      progress: prog,
      indeterminate: false,
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'android.intent.action.MEDIA_PREVIOUS',
          'Previous',
          showsUserInterface: false,
          cancelNotification: false,
          icon: DrawableResourceAndroidBitmap('ic_media_previous'),
        ),
        AndroidNotificationAction(
          'android.intent.action.MEDIA_PLAY_PAUSE',
          isPlaying ? 'Pause' : 'Play',
          showsUserInterface: false,
          cancelNotification: false,
          icon: DrawableResourceAndroidBitmap(isPlaying ? 'ic_media_pause' : 'ic_media_play'),
        ),
        const AndroidNotificationAction(
          'android.intent.action.MEDIA_NEXT',
          'Next',
          showsUserInterface: false,
          cancelNotification: false,
          icon: DrawableResourceAndroidBitmap('ic_media_next'),
        ),
        const AndroidNotificationAction(
          'android.intent.action.MEDIA_STOP',
          'Close',
          showsUserInterface: false,
          cancelNotification: false,
          icon: DrawableResourceAndroidBitmap('ic_media_close'),
        ),
      ],
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
