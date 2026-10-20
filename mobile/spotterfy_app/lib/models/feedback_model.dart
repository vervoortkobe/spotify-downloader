import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a piece of user feedback submitted through the app.
class FeedbackModel {
  final String id;
  final String userId;
  final String userEmail;
  final String userName;
  final String userPhotoUrl;
  final String message;
  final String type;
  final DateTime createdAt;
  bool isRead;
  final String platform;

  FeedbackModel({
    required this.id,
    required this.userId,
    required this.userEmail,
    required this.userName,
    this.userPhotoUrl = '',
    required this.message,
    this.type = 'feedback',
    required this.createdAt,
    this.isRead = false,
    this.platform = '',
  });

  factory FeedbackModel.fromFirestore(Map<String, dynamic> data, String id) {
    DateTime parsedDate;
    final created = data['createdAt'];
    if (created is Timestamp) {
      parsedDate = created.toDate();
    } else if (created is String) {
      parsedDate = DateTime.tryParse(created) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return FeedbackModel(
      id: id,
      userId: data['userId'] as String? ?? '',
      userEmail: data['userEmail'] as String? ?? '',
      userName: data['userName'] as String? ?? '',
      userPhotoUrl: data['userPhotoUrl'] as String? ?? '',
      message: data['message'] as String? ?? '',
      type: data['type'] as String? ?? 'feedback',
      createdAt: parsedDate,
      isRead: data['isRead'] as bool? ?? false,
      platform: data['platform'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'userId': userId,
    'userEmail': userEmail,
    'userName': userName,
    'userPhotoUrl': userPhotoUrl,
    'message': message,
    'type': type,
    'createdAt': Timestamp.fromDate(createdAt),
    'isRead': isRead,
    'platform': platform,
  };
}
