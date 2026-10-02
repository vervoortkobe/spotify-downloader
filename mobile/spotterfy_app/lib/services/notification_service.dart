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

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
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
      final android = _plugin!
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      try {
        await android?.requestNotificationsPermission();
      } catch (e) {
        debugPrint(
          '[NotificationService] requestNotificationsPermission failed (Activity not ready): $e',
        );
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
        debugPrint(
          '[NotificationService] createNotificationChannel failed: $e',
        );
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

    final sub =
        '${track.artists}  •  ${_posText(position)} / ${_posText(duration)}';

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
      largeIcon: track.cover.isNotEmpty
          ? null
          : const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
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
          icon: DrawableResourceAndroidBitmap(
            isPlaying ? 'ic_media_pause' : 'ic_media_play',
          ),
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

  // Download notification ID (different from playback)
  static const int _downloadNotificationId = 100;

  /// Shows a download progress notification.
  ///
  /// [progress] should be between 0.0 and 1.0, or null for indeterminate.
  /// [title] is the track/playlist title.
  /// [subtitle] is an optional subtitle (e.g., "Downloading...", "Saving...")
  /// [maxProgress] and [progressValue] can be used for specific byte counts.
  Future<void> showDownloadProgress({
    required String title,
    String? subtitle,
    double? progress, // 0.0 to 1.0, or null for indeterminate
    int? maxProgress,
    int? progressValue,
    bool isComplete = false,
    bool isError = false,
  }) async {
    if (!_initialized || _plugin == null) return;

    final isIndeterminate = progress == null;
    final prog = isIndeterminate ? 0 : (progress * 100).clamp(0, 100).toInt();
    final maxProg = maxProgress ?? 100;
    final progValue = progressValue ?? prog;

    final color = isError
        ? const Color(0xFFef4444)
        : (isComplete ? const Color(0xFF10b981) : const Color(0xFF3b82f6));

    final body =
        subtitle ??
        (isIndeterminate
            ? 'Downloading...'
            : (isComplete ? 'Download complete' : '$prog%'));

    final androidDetails = AndroidNotificationDetails(
      'download_channel',
      'Downloads',
      channelDescription: 'Download progress notifications',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: !isComplete && !isError,
      autoCancel: isComplete || isError,
      onlyAlertOnce: true,
      showWhen: false,
      playSound: isComplete && !isError,
      enableVibration: false,
      visibility: NotificationVisibility.public,
      color: color,
      colorized: true,
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      showProgress: !isComplete && !isError,
      maxProgress: maxProg,
      progress: progValue,
      indeterminate: isIndeterminate,
      styleInformation: BigTextStyleInformation(
        body,
        htmlFormatBigText: true,
        htmlFormatTitle: true,
        contentTitle: title,
        htmlFormatContentTitle: true,
      ),
    );

    await _plugin!.show(
      id: _downloadNotificationId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: androidDetails),
    );
  }

  /// Cancels the download notification.
  Future<void> cancelDownloadNotification() async {
    if (_plugin != null) {
      await _plugin!.cancel(id: _downloadNotificationId);
    }
  }
}
