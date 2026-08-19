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
    }

    _initialized = true;
  }

  void _onNotificationResponse(NotificationResponse response) {
    switch (response.actionId) {
      case 'play_pause':
        onPlayPause?.call();
        break;
      case 'next':
        onNext?.call();
        break;
      case 'previous':
        onPrevious?.call();
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
      importance: Importance.low,
      priority: Priority.defaultPriority,
      ongoing: true,
      showWhen: false,
      usesChronometer: false,
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction('previous', 'Prev',
            showsUserInterface: false),
        AndroidNotificationAction(
            'play_pause', isPlaying ? 'Pause' : 'Play',
            showsUserInterface: false),
        const AndroidNotificationAction('next', 'Next',
            showsUserInterface: false),
      ],
      styleInformation: const MediaStyleInformation(),
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
