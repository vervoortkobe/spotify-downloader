class UserModel {
  final String uid;
  final String email;
  String displayName;
  String photoUrl;
  String spotifyProfileUrl;
  bool isAdmin;
  bool isApproved;
  final DateTime createdAt;
  String? currentListeningTo;
  String? currentJamSession;
  DateTime? lastSpotifySync;

  UserModel({
    required this.uid,
    required this.email,
    this.displayName = '',
    this.photoUrl = '',
    this.spotifyProfileUrl = '',
    this.isAdmin = false,
    this.isApproved = false,
    DateTime? createdAt,
    this.currentListeningTo,
    this.currentJamSession,
    this.lastSpotifySync,
  }) : createdAt = createdAt ?? DateTime.now();

  factory UserModel.fromFirestore(Map<String, dynamic> data, String uid) => UserModel(
    uid: uid,
    email: data['email'] as String? ?? '',
    displayName: data['displayName'] as String? ?? '',
    photoUrl: data['photoUrl'] as String? ?? '',
    spotifyProfileUrl: data['spotifyProfileUrl'] as String? ?? '',
    isAdmin: data['isAdmin'] as bool? ?? false,
    isApproved: data['isApproved'] as bool? ?? false,
    createdAt: (data['createdAt'] as dynamic)?.toDate() ?? DateTime.now(),
    currentListeningTo: data['currentListeningTo'] as String?,
    currentJamSession: data['currentJamSession'] as String?,
    lastSpotifySync: (data['lastSpotifySync'] as dynamic)?.toDate(),
  );

  Map<String, dynamic> toFirestore() => {
    'email': email,
    'displayName': displayName,
    'photoUrl': photoUrl,
    'spotifyProfileUrl': spotifyProfileUrl,
    'isAdmin': isAdmin,
    'isApproved': isApproved,
    'createdAt': createdAt,
    'currentListeningTo': currentListeningTo,
    'currentJamSession': currentJamSession,
    'lastSpotifySync': lastSpotifySync,
  };
}
