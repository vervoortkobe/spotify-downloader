import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotterfy_app/models/user_model.dart';
import 'package:spotterfy_app/providers/admin_provider.dart';
import 'package:spotterfy_app/services/admin_service.dart';

UserModel _user({
  required String uid,
  String name = 'Test',
  String email = 'test@example.com',
  bool admin = false,
  bool approved = true,
  bool banned = false,
  bool onboarded = true,
  String? listeningTo,
  String? jam,
  String spotify = '',
  int ageDays = 0,
}) => UserModel(
  uid: uid,
  email: email,
  displayName: name,
  isAdmin: admin,
  isApproved: approved,
  isBanned: banned,
  hasCompletedOnboarding: onboarded,
  currentListeningTo: listeningTo,
  currentJamSession: jam,
  spotifyProfileUrl: spotify,
  createdAt: DateTime.now().subtract(Duration(days: ageDays)),
);

/// Provider wired to an in-memory Firestore, already loaded, so the moderation
/// writes are actually exercised rather than mocked away.
Future<AdminProvider> _providerWith(List<UserModel> users) async {
  final firestore = FakeFirebaseFirestore();
  for (final u in users) {
    firestore.collection('users').doc(u.uid).set(u.toFirestore());
  }
  final provider = AdminProvider(AdminService(firestore));
  await provider.loadUsers();
  return provider;
}

void main() {
  group('AdminProvider stats', () {
    test('counts each category across the whole user base', () async {
      final admin = await _providerWith([
        _user(uid: 'a', name: 'Ada', ageDays: 1),
        _user(uid: 'b', name: 'Bob', admin: true, banned: true),
        _user(uid: 'c', name: 'Cleo', approved: false),
        _user(
          uid: 'd',
          name: 'Dan',
          listeningTo: 'song-1',
          spotify: 'https://open.spotify.com/x',
        ),
        _user(uid: 'e', name: 'Eve', jam: 'jam-1'),
        _user(uid: 'f', name: ' Fay', ageDays: 30),
      ]);

      final s = admin.stats;
      expect(s.total, 6);
      expect(s.admins, 1);
      expect(s.banned, 1);
      expect(s.pending, 1);
      expect(s.activeNow, 1);
      expect(s.newThisWeek, 5); // only 'f' is older than 7 days
      expect(s.spotifyLinked, 1);
      expect(s.inJam, 1);
    });

    test(
      'stats ignore the active filter and describe the whole base',
      () async {
        final admin = await _providerWith([
          _user(uid: 'a'),
          _user(uid: 'b', banned: true),
          _user(uid: 'c'),
        ]);
        admin.setFilter(AdminFilter.banned);
        expect(admin.visibleUsers.length, 1);
        // The grid is an overview, not a view of the current filter.
        expect(admin.stats.total, 3);
        expect(admin.stats.banned, 1);
      },
    );
  });

  group('AdminProvider search and filter', () {
    late AdminProvider admin;

    setUp(() async {
      admin = await _providerWith([
        _user(uid: 'u1', name: 'Alpha', email: 'alpha@x.com'),
        _user(uid: 'u2', name: 'Beta', email: 'beta@x.com', banned: true),
        _user(uid: 'u3', name: 'Gamma', listeningTo: 'song-9'),
        _user(uid: 'u4', name: 'Delta', admin: true),
      ]);
    });

    test('search matches name and email case-insensitively', () {
      admin.search('alp');
      expect(admin.visibleUsers.single.uid, 'u1');
      admin.search('BETA@X.COM');
      expect(admin.visibleUsers.single.uid, 'u2');
    });

    test('search also matches a raw uid', () {
      // Admins often paste a uid from a log or a report.
      admin.search('u4');
      expect(admin.visibleUsers.single.uid, 'u4');
    });

    test('search matches the Spotify profile url', () async {
      final a2 = await _providerWith([
        _user(uid: 'z', spotify: 'https://open.spotify.com/user/spot'),
      ]);
      a2.search('user/spot');
      expect(a2.visibleUsers.single.uid, 'z');
    });

    test('filter chips narrow to the right set', () {
      admin.setFilter(AdminFilter.banned);
      expect(admin.visibleUsers.map((u) => u.uid), ['u2']);
      admin.setFilter(AdminFilter.admins);
      expect(admin.visibleUsers.map((u) => u.uid), ['u4']);
      admin.setFilter(AdminFilter.active);
      expect(admin.visibleUsers.map((u) => u.uid), ['u3']);
    });

    test('search and filter combine rather than replacing each other', () {
      admin.setFilter(AdminFilter.banned);
      admin.search('beta');
      expect(admin.visibleUsers.single.uid, 'u2');
      admin.search('gamma');
      expect(admin.visibleUsers, isEmpty);
    });

    test('counts stay accurate per filter', () {
      expect(admin.countFor(AdminFilter.all), 4);
      expect(admin.countFor(AdminFilter.banned), 1);
      expect(admin.countFor(AdminFilter.admins), 1);
      expect(admin.countFor(AdminFilter.active), 1);
    });

    test('sorting orders by name and by newest/oldest', () {
      admin.setSort(AdminSort.name);
      expect(admin.visibleUsers.map((u) => u.displayName), [
        'Alpha',
        'Beta',
        'Delta',
        'Gamma',
      ]);
      admin.setSort(AdminSort.newest);
      expect(admin.visibleUsers.length, 4);
    });

    test('active-first sort puts playing users on top', () {
      admin.setSort(AdminSort.active);
      expect(admin.visibleUsers.first.uid, 'u3');
    });
  });

  group('AdminProvider moderation', () {
    test(
      'ban writes through to Firestore and updates the cached list',
      () async {
        final admin = await _providerWith([_user(uid: 'a', name: 'Ada')]);
        await admin.banUser('a', 'Spamming playlists');

        final doc = admin.userByUid('a');
        expect(doc!.isBanned, isTrue);
        expect(doc.bannedReason, 'Spamming playlists');
        expect(doc.bannedAt, isNotNull);
      },
    );

    test('unban clears the flag, timestamp and stale reason', () async {
      final admin = await _providerWith([_user(uid: 'a', banned: true)]);
      admin.userByUid('a')!.bannedReason = 'old reason';
      await admin.unbanUser('a');

      final doc = admin.userByUid('a');
      expect(doc!.isBanned, isFalse);
      expect(doc.bannedAt, isNull);
      expect(doc.bannedReason, isEmpty);
    });

    test('promote and demote admin', () async {
      final admin = await _providerWith([_user(uid: 'a')]);
      await admin.setAdmin('a', true);
      expect(admin.userByUid('a')!.isAdmin, isTrue);
      await admin.setAdmin('a', false);
      expect(admin.userByUid('a')!.isAdmin, isFalse);
    });

    test('approve toggle', () async {
      final admin = await _providerWith([_user(uid: 'a', approved: false)]);
      await admin.setApproved('a', true);
      expect(admin.userByUid('a')!.isApproved, isTrue);
    });

    test('rename', () async {
      final admin = await _providerWith([_user(uid: 'a', name: 'Old')]);
      await admin.setDisplayName('a', 'New');
      expect(admin.userByUid('a')!.displayName, 'New');
    });

    test('busyUid is cleared so the row spinner cannot stick', () async {
      final admin = await _providerWith([_user(uid: 'a')]);
      expect(admin.busyUid, isNull);
      await admin.setAdmin('a', true);
      expect(admin.busyUid, isNull);
    });

    test(
      'a banned user still shows their stats in the filtered view',
      () async {
        final admin = await _providerWith([_user(uid: 'a')]);
        await admin.banUser('a', 'abuse');
        admin.setFilter(AdminFilter.banned);
        expect(admin.visibleUsers.single.uid, 'a');
      },
    );
  });

  group('UserModel moderation fields', () {
    test('defaults are safe for documents written before bans existed', () {
      final u = UserModel.fromFirestore(const {'email': 'a@b.c'}, 'uid');
      expect(u.isBanned, isFalse);
      expect(u.bannedAt, isNull);
      expect(u.bannedReason, isEmpty);
    });

    test('a non-bool isBanned does not throw the whole list away', () {
      // A hand-edited document must not take the admin panel down with it.
      final u = UserModel.fromFirestore(const {'isBanned': 'true'}, 'uid');
      expect(u.isBanned, isTrue);
      final n = UserModel.fromFirestore(const {'isBanned': 1}, 'uid');
      expect(n.isBanned, isTrue);
    });

    test('isActiveNow treats an empty listening-to as inactive', () {
      expect(_user(uid: 'a').isActiveNow, isFalse);
      expect(_user(uid: 'a', listeningTo: 'x').isActiveNow, isTrue);
    });
  });

  group('AdminService.getAllUsers', () {
    test('skips a malformed document instead of failing the list', () async {
      final firestore = FakeFirebaseFirestore();
      firestore
          .collection('users')
          .doc('ok')
          .set(_user(uid: 'ok').toFirestore());
      // A doc missing every field still parses defensively.
      firestore.collection('users').doc('bare').set({'weird': true});

      final service = AdminService(firestore);
      final users = await service.getAllUsers();
      expect(users.any((u) => u.uid == 'ok'), isTrue);
    });

    test('returns newest first', () async {
      final firestore = FakeFirebaseFirestore();
      firestore
          .collection('users')
          .doc('old')
          .set(_user(uid: 'old', ageDays: 30).toFirestore());
      firestore
          .collection('users')
          .doc('new')
          .set(_user(uid: 'new', ageDays: 1).toFirestore());
      final users = await AdminService(firestore).getAllUsers();
      expect(users.first.uid, 'new');
    });
  });
}
