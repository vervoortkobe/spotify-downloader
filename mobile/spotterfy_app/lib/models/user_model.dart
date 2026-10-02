class UserModel {
  final String uid;
  final String email;
  String displayName;
  String photoUrl;
  String spotifyProfileUrl;
  bool isAdmin;
  bool isApproved;
  bool hasCompletedOnboarding;
  final DateTime createdAt;
  String? currentListeningTo;
  String? currentJamSession;
  DateTime? lastSpotifySync;

  /// Moderation block set from the admin panel.
  ///
  /// Absent in older documents, which is why it defaults to false rather than
  /// being required. Enforced in [AuthProvider.needsModeration] on the way in.
  bool isBanned;
  DateTime? bannedAt;

  /// Why the account was suspended, shown to the user so a ban is never silent.
  String bannedReason;

  UserModel({
    required this.uid,
    required this.email,
    this.displayName = '',
    this.photoUrl = '',
    this.spotifyProfileUrl = '',
    this.isAdmin = false,
    this.isApproved = false,
    this.hasCompletedOnboarding = false,
    DateTime? createdAt,
    this.currentListeningTo,
    this.currentJamSession,
    this.lastSpotifySync,
    this.isBanned = false,
    this.bannedAt,
    this.bannedReason = '',
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
    isApproved: data['isApproved'] as bool? ?? false,
    hasCompletedOnboarding: data['hasCompletedOnboarding'] as bool? ?? false,
    createdAt: (data['createdAt'] as dynamic)?.toDate() ?? DateTime.now(),
    currentListeningTo: data['currentListeningTo'] as String?,
    currentJamSession: data['currentJamSession'] as String?,
    lastSpotifySync: (data['lastSpotifySync'] as dynamic)?.toDate(),
    // Read through a helper: a hand-edited doc with a non-bool here must not
    // throw and wipe out the whole user list the admin is looking at.
    isBanned: _bool(data['isBanned']),
    bannedAt: (data['bannedAt'] as dynamic)?.toDate(),
    bannedReason: data['bannedReason'] as String? ?? '',
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
    'isApproved': isApproved,
    'hasCompletedOnboarding': hasCompletedOnboarding,
    'createdAt': createdAt,
    'currentListeningTo': currentListeningTo,
    'currentJamSession': currentJamSession,
    'lastSpotifySync': lastSpotifySync,
    'isBanned': isBanned,
    'bannedAt': bannedAt,
    'bannedReason': bannedReason,
  };

  /// True while something is playing for this user.
  bool get isActiveNow => (currentListeningTo ?? '').isNotEmpty;
}
