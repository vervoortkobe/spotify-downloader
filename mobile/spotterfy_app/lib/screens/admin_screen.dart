import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/models/user_model.dart';
import 'package:spotterfy_app/providers/admin_provider.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/screens/profile_screen.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/app_chrome.dart';

/// Admin tools: user stats, search across every account, and moderation.
///
/// Reached from Settings rather than as the app's root, so an admin can use the
/// app normally and drop into these tools when needed.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AdminProvider>().loadUsers();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();
    final myUid = context.select<AuthProvider, String?>((a) => a.user?.uid);

    return HideAppChrome(
      child: Scaffold(
        backgroundColor: SpotterfyTheme.pageBackground,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'Admin',
            style: TextStyle(
              color: SpotterfyTheme.text,
              fontWeight: FontWeight.w800,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Reload',
              icon: Icon(Icons.refresh, color: SpotterfyTheme.text),
              onPressed: admin.isLoading ? null : () => admin.refresh(),
            ),
          ],
        ),
        body: admin.isLoading && admin.users.isEmpty
            ? Center(
                child: CircularProgressIndicator(color: SpotterfyTheme.primary),
              )
            : RefreshIndicator(
                color: SpotterfyTheme.primary,
                backgroundColor: SpotterfyTheme.surface,
                onRefresh: () => admin.refresh(),
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _statsGrid(admin.stats)),
                    SliverToBoxAdapter(child: _searchRow(admin)),
                    SliverToBoxAdapter(child: _filterChips(admin)),
                    if (admin.error != null)
                      SliverToBoxAdapter(child: _errorBanner(admin.error!)),
                    SliverToBoxAdapter(child: _listHeader(admin)),
                    ..._userSlivers(admin, myUid),
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                  ],
                ),
              ),
      ),
    );
  }

  // --- Stats ---------------------------------------------------------------

  Widget _statsGrid(AdminStats s) {
    final tiles = <(String, String, IconData, Color)>[
      ('Total', '${s.total}', Icons.people, SpotterfyTheme.primary),
      (
        'Active now',
        '${s.activeNow}',
        Icons.graphic_eq,
        const Color(0xFF38bdf8),
      ),
      (
        'New (7d)',
        '${s.newThisWeek}',
        Icons.fiber_new,
        const Color(0xFFa3e635),
      ),
      ('Admins', '${s.admins}', Icons.shield, const Color(0xFFc084fc)),
      ('Suspended', '${s.banned}', Icons.gpp_maybe, const Color(0xFFef4444)),
      ('Spotify', '${s.spotifyLinked}', Icons.link, SpotterfyTheme.primary),
      ('In a jam', '${s.inJam}', Icons.groups, const Color(0xFFf472b6)),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 4,
        childAspectRatio: 0.95,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        children: [
          for (final t in tiles)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color: SpotterfyTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.$4.withValues(alpha: 0.25)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(t.$3, color: t.$4, size: 18),
                  const SizedBox(height: 4),
                  FittedBox(
                    child: Text(
                      t.$2,
                      style: TextStyle(
                        color: SpotterfyTheme.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    child: Text(
                      t.$1,
                      style: TextStyle(
                        color: SpotterfyTheme.mutedDark,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // --- Search / filter / sort ---------------------------------------------

  Widget _searchRow(AdminProvider admin) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: admin.search,
              style: TextStyle(color: SpotterfyTheme.text, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search name, email, uid or Spotify URL',
                hintStyle: TextStyle(
                  color: SpotterfyTheme.mutedDark,
                  fontSize: 13,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: SpotterfyTheme.mutedDark,
                  size: 18,
                ),
                suffixIcon: admin.query.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: SpotterfyTheme.mutedDark,
                          size: 16,
                        ),
                        onPressed: () {
                          _searchCtrl.clear();
                          admin.search('');
                        },
                      ),
                filled: true,
                fillColor: SpotterfyTheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _sortButton(admin),
        ],
      ),
    );
  }

  Widget _sortButton(AdminProvider admin) {
    return Tooltip(
      message: 'Sort',
      child: Material(
        color: SpotterfyTheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showSortSheet(admin),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.sort, color: SpotterfyTheme.text, size: 20),
          ),
        ),
      ),
    );
  }

  void _showSortSheet(AdminProvider admin) {
    // useRootNavigator so the sheet clears the mini player, which is drawn
    // outside this tab's navigator and would otherwise cover the options.
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: SpotterfyTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: SpotterfyTheme.overlay(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Sort users by',
              style: TextStyle(
                color: SpotterfyTheme.text,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            for (final s in AdminSort.values)
              ListTile(
                dense: true,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  admin.setSort(s);
                },
                title: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: admin.sort == s
                          ? Icon(
                              Icons.check,
                              size: 18,
                              color: SpotterfyTheme.primary,
                            )
                          : null,
                    ),
                    Text(
                      s.label,
                      style: TextStyle(
                        color: SpotterfyTheme.text,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _filterChips(AdminProvider admin) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          for (final f in AdminFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _chip(
                label: '${f.label} (${admin.countFor(f)})',
                selected: admin.filter == f,
                onTap: () => admin.setFilter(f),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? SpotterfyTheme.primary.withValues(alpha: 0.18)
              : SpotterfyTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? SpotterfyTheme.primary
                : SpotterfyTheme.overlay(0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? SpotterfyTheme.primary : SpotterfyTheme.text,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFef4444).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFef4444).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFef4444), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: SpotterfyTheme.text, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _listHeader(AdminProvider admin) {
    final n = admin.visibleUsers.length;
    final total = admin.totalCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        n == total ? '$total users' : '$n of $total users',
        style: TextStyle(
          color: SpotterfyTheme.mutedDark,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  List<Widget> _userSlivers(AdminProvider admin, String? myUid) {
    final rows = admin.visibleUsers;
    if (rows.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
            child: Column(
              children: [
                Icon(
                  Icons.person_search,
                  color: SpotterfyTheme.mutedDark,
                  size: 40,
                ),
                const SizedBox(height: 12),
                Text(
                  admin.query.isEmpty
                      ? 'No users match this filter'
                      : 'No users match "${admin.query}"',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: SpotterfyTheme.mutedDark,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    return [
      SliverList.separated(
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _userRow(rows[i], admin, rows[i].uid == myUid),
        ),
      ),
    ];
  }

  Widget _userRow(UserModel u, AdminProvider admin, bool isMe) {
    final busy = admin.busyUid == u.uid;
    final initial = u.displayName.trim().isEmpty
        ? (u.email.isEmpty ? '?' : u.email[0])
        : u.displayName.trim()[0];

    return Material(
      color: SpotterfyTheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: busy ? null : () => _showUserSheet(u, admin),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: SpotterfyTheme.borderColor,
                backgroundImage: u.photoUrl.isNotEmpty
                    ? NetworkImage(u.photoUrl)
                    : null,
                child: u.photoUrl.isEmpty
                    ? Text(
                        initial.toUpperCase(),
                        style: TextStyle(
                          color: SpotterfyTheme.text,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            u.displayName.isEmpty ? 'No name' : u.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: SpotterfyTheme.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 6),
                          const _Tag('You', Color(0xFF38bdf8)),
                        ],
                        if (u.isAdmin) ...[
                          const SizedBox(width: 6),
                          const _Tag('Admin', Color(0xFFc084fc)),
                        ],
                        if (u.isBanned) ...[
                          const SizedBox(width: 6),
                          const _Tag('Suspended', Color(0xFFef4444)),
                        ],
                        if (u.isActiveNow) ...[
                          const SizedBox(width: 6),
                          _Tag('Active', SpotterfyTheme.primary),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      u.email.isEmpty ? u.uid : u.email,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: SpotterfyTheme.mutedDark,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      'Joined ${_ago(u.createdAt)}',
                      style: const TextStyle(
                        color: Color(0xFF71717a),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: SpotterfyTheme.primary,
                  ),
                )
              else
                Icon(
                  Icons.chevron_right,
                  color: SpotterfyTheme.mutedDark,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }

  // --- Moderation actions --------------------------------------------------

  Future<void> _showUserSheet(UserModel u, AdminProvider admin) async {
    // Re-read before opening: the cached object may be stale after a previous
    // action in this same session.
    final fresh = admin.userByUid(u.uid) ?? u;
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: SpotterfyTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Consumer<AdminProvider>(
        builder: (context, live, _) {
          final target = live.userByUid(u.uid) ?? fresh;
          final busy = live.busyUid == u.uid;
          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: SpotterfyTheme.overlay(0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _sheetHeader(target),
                    const SizedBox(height: 16),
                    _action(
                      icon: Icons.person,
                      color: const Color(0xFF38bdf8),
                      label: 'View profile',
                      subtitle: 'Playlists and public details',
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        Navigator.push(
                          context,
                          swipeRoute(ProfileScreen(uid: target.uid)),
                        );
                      },
                    ),
                    _action(
                      icon: Icons.drive_file_rename_outline,
                      color: const Color(0xFFfbbf24),
                      label: 'Rename',
                      subtitle: 'Change their display name',
                      onTap: busy
                          ? null
                          : () async {
                              Navigator.pop(sheetCtx);
                              final name = await _promptName(target);
                              if (name != null) {
                                await admin.setDisplayName(target.uid, name);
                              }
                            },
                    ),
                    _action(
                      icon: Icons.shield,
                      color: const Color(0xFFc084fc),
                      label: target.isAdmin ? 'Revoke admin' : 'Make admin',
                      subtitle: target.isAdmin
                          ? 'Removes access to these tools'
                          : 'Grants access to these tools',
                      onTap: busy
                          ? null
                          : () {
                              Navigator.pop(sheetCtx);
                              _confirm(
                                title: target.isAdmin
                                    ? 'Revoke admin?'
                                    : 'Make ${target.displayName.isEmpty ? 'this user' : target.displayName} an admin?',
                                body: target.isAdmin
                                    ? 'They will lose access to the admin panel.'
                                    : 'They will be able to moderate every account.',
                                confirmLabel: target.isAdmin
                                    ? 'Revoke'
                                    : 'Make admin',
                                onConfirm: () =>
                                    admin.setAdmin(target.uid, !target.isAdmin),
                              );
                            },
                    ),
                    _action(
                      icon: target.isBanned ? Icons.lock_open : Icons.gpp_bad,
                      color: const Color(0xFFef4444),
                      label: target.isBanned ? 'Lift suspension' : 'Suspend',
                      subtitle: target.isBanned
                          ? 'Restore their access'
                          : 'Blocks the app on their next launch',
                      danger: !target.isBanned,
                      onTap: busy
                          ? null
                          : () {
                              if (target.isBanned) {
                                Navigator.pop(sheetCtx);
                                admin.unbanUser(target.uid);
                              } else {
                                Navigator.pop(sheetCtx);
                                _promptBan(target, admin);
                              }
                            },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sheetHeader(UserModel u) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: SpotterfyTheme.borderColor,
              backgroundImage: u.photoUrl.isNotEmpty
                  ? NetworkImage(u.photoUrl)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    u.displayName.isEmpty ? 'No name' : u.displayName,
                    style: TextStyle(
                      color: SpotterfyTheme.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    u.email.isEmpty ? 'No email' : u.email,
                    style: TextStyle(
                      color: SpotterfyTheme.mutedDark,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _kv('UID', u.uid),
        _kv('Joined', _plainDate(u.createdAt)),
        _kv('Spotify', u.spotifyProfileUrl.isEmpty ? 'Not linked' : 'Linked'),
        _kv('Onboarding', u.hasCompletedOnboarding ? 'Complete' : 'Incomplete'),
        if (u.isBanned) ...[
          _kv('Suspended', _agoOrDate(u.bannedAt)),
          if (u.bannedReason.isNotEmpty) _kv('Reason', u.bannedReason),
        ],
        if (u.lastSpotifySync != null)
          _kv('Last sync', _agoOrDate(u.lastSpotifySync)),
      ],
    );
  }

  /// Timestamp without the fractional seconds, which are just noise here.
  static String _plainDate(DateTime d) =>
      d.toLocal().toString().split('.').first;

  static String _agoOrDate(DateTime? d) =>
      d == null ? 'unknown' : _plainDate(d);

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(color: SpotterfyTheme.mutedDark, fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: SpotterfyTheme.text, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required Color color,
    required String label,
    required String subtitle,
    required VoidCallback? onTap,
    bool danger = false,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: onTap != null,
      onTap: onTap,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 19),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: danger ? const Color(0xFFef4444) : SpotterfyTheme.text,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: SpotterfyTheme.mutedDark, fontSize: 11),
      ),
    );
  }

  /// Suspends [u] after capturing a reason, which is shown to them.
  Future<void> _promptBan(UserModel u, AdminProvider admin) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => const _SuspendDialog(),
    );
    if (reason == null) return;
    await admin.banUser(
      u.uid,
      reason.isEmpty
          ? 'This account has been suspended. Contact support if you think this is a mistake.'
          : reason,
    );
  }

  Future<String?> _promptName(UserModel u) async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenameDialog(initial: u.displayName),
    );
    if (name == null || name.isEmpty || name == u.displayName) return null;
    return name;
  }

  void _confirm({
    required String title,
    required String body,
    required String confirmLabel,
    required Future<void> Function() onConfirm,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotterfyTheme.surface,
        title: Text(title, style: TextStyle(color: SpotterfyTheme.text)),
        content: Text(body, style: TextStyle(color: SpotterfyTheme.mutedDark)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: SpotterfyTheme.mutedDark),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await onConfirm();
            },
            child: Text(
              confirmLabel,
              style: const TextStyle(color: Color(0xFFef4444)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Dialogs that own their own [TextEditingController].
///
/// The controller used to be created by the caller and disposed right after
/// `await showDialog(...)` returned. That future completes the moment the route
/// is popped, but the reverse transition keeps the `TextField` mounted for a few
/// more frames - so the controller was disposed while `EditableText` was still a
/// dependent and Flutter threw
/// `dependents.isEmpty: is not true` on every save. A StatefulWidget ties the
/// controller's lifetime to the widget that actually uses it.
class _RenameDialog extends StatefulWidget {
  final String initial;
  const _RenameDialog({required this.initial});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: SpotterfyTheme.surface,
      title: const Text('Rename account'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: TextStyle(color: SpotterfyTheme.text),
        decoration: InputDecoration(
          hintText: 'Display name',
          hintStyle: TextStyle(color: SpotterfyTheme.mutedDark),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(color: SpotterfyTheme.mutedDark),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text('Save', style: TextStyle(color: SpotterfyTheme.primary)),
        ),
      ],
    );
  }
}

class _SuspendDialog extends StatefulWidget {
  const _SuspendDialog();

  @override
  State<_SuspendDialog> createState() => _SuspendDialogState();
}

class _SuspendDialogState extends State<_SuspendDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: SpotterfyTheme.surface,
      title: const Text('Suspend account'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'They will be blocked from the app the next time it opens. '
            'The reason below is shown to them.',
            style: TextStyle(color: SpotterfyTheme.mutedDark, fontSize: 12),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 3,
            minLines: 2,
            style: TextStyle(color: SpotterfyTheme.text),
            decoration: InputDecoration(
              hintText: 'Reason (shown to the user)',
              hintStyle: TextStyle(color: SpotterfyTheme.mutedDark),
              filled: true,
              fillColor: SpotterfyTheme.pageBackground,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(color: SpotterfyTheme.mutedDark),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text(
            'Suspend',
            style: TextStyle(color: Color(0xFFef4444)),
          ),
        ),
      ],
    );
  }
}
