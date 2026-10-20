class UserModel {
  final String uid;
  final String email;
  String displayName;
  String photoUrl;
  String spotifyProfileUrl;
  bool isAdmin;
  final DateTime createdAt;
  String? currentListeningTo;
  String? currentJamSession;
  bool isOnline;
  DateTime? lastActiveAt;
  String currentTrackTitle;
  String currentTrackArtist;
  String currentTrackArtwork;

  /// Moderation block set from the admin panel.
  ///
  /// Absent in older documents, which is why it defaults to false rather than
  /// being required. Enforced in [AuthProvider.needsModeration] on the way in.
  bool isSuspended;
  DateTime? suspendedAt;

  /// Why the account was suspended, shown to the user.
  String suspendedReason;

  UserModel({
    required this.uid,
    required this.email,
    this.displayName = '',
    this.photoUrl = '',
    this.spotifyProfileUrl = '',
    this.isAdmin = false,
    DateTime? createdAt,
    this.currentListeningTo,
    this.currentJamSession,
    this.isOnline = false,
    this.lastActiveAt,
    this.currentTrackTitle = '',
    this.currentTrackArtist = '',
    this.currentTrackArtwork = '',
    this.isSuspended = false,
    this.suspendedAt,
    this.suspendedReason = '',
  }) : createdAt = createdAt ?? DateTime.now();

  factory UserModel.fromFirestore(
    Map<String, dynamic> data,
    String uid,
  ) => UserModel(
    uid: uid,
    email: data['email'] as String? ?? '',
    displayName: data['displayName'] as String? ?? '',
    photoUrl: data['photoUrl'] as String? ?? '',
    spotifyProfileUrl: data['spotifyProfileUrl'] as String? ?? '',
    isAdmin: data['isAdmin'] as bool? ?? false,
    createdAt: (data['createdAt'] as dynamic)?.toDate() ?? DateTime.now(),
    currentListeningTo: data['currentListeningTo'] as String?,
    currentJamSession: data['currentJamSession'] as String?,
    isOnline: _bool(data['isOnline']),
    lastActiveAt: (data['lastActiveAt'] as dynamic)?.toDate(),
    currentTrackTitle: data['currentTrackTitle'] as String? ?? '',
    currentTrackArtist: data['currentTrackArtist'] as String? ?? '',
    currentTrackArtwork: data['currentTrackArtwork'] as String? ?? '',
    // Read through a helper: a hand-edited doc with a non-bool here must not
    // throw and wipe out the whole user list the admin is looking at.
    isSuspended: _bool(data['isSuspended']),
    suspendedAt: (data['suspendedAt'] as dynamic)?.toDate(),
    suspendedReason: data['suspendedReason'] as String? ?? '',
  );

  static bool _bool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v == 'true' || v == '1';
    return false;
  }

  Map<String, dynamic> toFirestore() => {
    'email': email,
    'displayName': displayName,
    'photoUrl': photoUrl,
    'spotifyProfileUrl': spotifyProfileUrl,
    'isAdmin': isAdmin,
    'createdAt': createdAt,
    'isSuspended': isSuspended,
    'suspendedAt': suspendedAt,
    'suspendedReason': suspendedReason,
  };

  /// True while something is playing for this user.
  bool get isActiveNow => (currentListeningTo ?? '').isNotEmpty;

  /// Ignore stale online flags if the client crashed before it could go offline.
  bool get isOnlineNow =>
      isOnline &&
      lastActiveAt != null &&
      DateTime.now().difference(lastActiveAt!) < const Duration(minutes: 3);
}
