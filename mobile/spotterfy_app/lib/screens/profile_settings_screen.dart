import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/app_background.dart';

/// The account details that used to be three loose rows on the Settings page.
///
/// Grouped here so "Profile" is one destination: your identity, the fields that
/// describe it, and where to change them. Each row shows its current value
/// inline, so the settings list can stay a one-line summary.
class ProfileSettingsScreen extends StatelessWidget {
  const ProfileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final name = user?.displayName ?? '';
    final spotifyUrl = user?.spotifyProfileUrl ?? '';
    final photoUrl = user?.photoUrl ?? '';

    return AppGradientScaffold(
      title: 'Profile',
      body: SingleChildScrollView(
        // Clears the mini player drawn over this page by MainScreen.
        padding: const EdgeInsets.only(bottom: 140),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: _avatar(photoUrl, name)),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  name.isEmpty ? 'No name set' : name,
                  style: TextStyle(
                    color: SpotterfyTheme.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (user?.email.isNotEmpty ?? false)
                Center(
                  child: Text(
                    user!.email,
                    style: TextStyle(color: SpotterfyTheme.muted),
                  ),
                ),
              const SizedBox(height: 28),
              _label('Details'),
              _row(
                icon: Icons.badge_outlined,
                title: 'Name',
                subtitle: name.isEmpty ? 'Not set' : name,
                onTap: () => _editName(context, auth, name),
              ),
              const SizedBox(height: 12),
              _row(
                icon: Icons.link,
                title: 'Spotify URL',
                subtitle: spotifyUrl.isEmpty ? 'Not linked' : spotifyUrl,
                onTap: () => _editSpotifyUrl(context, auth, spotifyUrl),
              ),
              const SizedBox(height: 28),
              _label('Account'),
              _row(
                icon: Icons.alternate_email,
                title: 'Email',
                subtitle: (user?.email.isNotEmpty ?? false)
                    ? user!.email
                    : 'Not available',
                // Sign-in identity, not something the user can type here.
                onTap: null,
              ),
              const SizedBox(height: 12),
              if (user?.createdAt != null) ...[
                _row(
                  icon: Icons.cake_outlined,
                  title: 'Joined',
                  subtitle: _date(user!.createdAt),
                  onTap: null,
                ),
                const SizedBox(height: 12),
              ],
              if (auth.isAdmin)
                _row(
                  icon: Icons.shield_outlined,
                  title: 'Role',
                  subtitle: 'Administrator',
                  onTap: null,
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _avatar(String photoUrl, String name) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: SpotterfyTheme.card,
        border: Border.all(color: SpotterfyTheme.mutedDark, width: 2),
        image: photoUrl.isNotEmpty
            ? DecorationImage(image: NetworkImage(photoUrl), fit: BoxFit.cover)
            : null,
      ),
      child: photoUrl.isEmpty
          ? Text(
              initial,
              style: TextStyle(
                color: SpotterfyTheme.muted,
                fontSize: 36,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }

  static Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        color: SpotterfyTheme.muted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  static Widget _row({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return Opacity(
      // Read-only rows are dimmed rather than hidden: the value is still useful
      // context, it just cannot be changed here.
      opacity: onTap == null ? 0.6 : 1,
      child: Material(
        color: SpotterfyTheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            child: Row(
              children: [
                Icon(icon, color: SpotterfyTheme.muted, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: SpotterfyTheme.text,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: SpotterfyTheme.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.chevron_right,
                    color: SpotterfyTheme.muted,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _editName(
    BuildContext context,
    AuthProvider auth,
    String current,
  ) async {
    final value = await _prompt(
      context,
      title: 'Edit display name',
      hint: 'Display name',
      initial: current,
      confirmLabel: 'Save',
    );
    if (value == null) return;
    // The dialog above was awaited, so `context` has to be re-checked before use.
    if (!context.mounted) return;

    if (value.trim().length < 3) {
      _toast(context, 'Name must be at least 3 characters');
      return;
    }
    try {
      await auth.updateDisplayName(value.trim());
      if (context.mounted) _toast(context, 'Display name updated');
    } catch (e) {
      if (context.mounted) _toast(context, '$e');
    }
  }

  Future<void> _editSpotifyUrl(
    BuildContext context,
    AuthProvider auth,
    String current,
  ) async {
    final value = await _prompt(
      context,
      title: 'Edit Spotify URL',
      hint: 'Spotify profile URL',
      initial: current,
      confirmLabel: 'Save',
    );
    if (value == null) return;
    // The dialog above was awaited, so `context` has to be re-checked before use.
    if (!context.mounted) return;

    final trimmed = value.trim();
    if (trimmed.isNotEmpty && !trimmed.contains('open.spotify.com')) {
      _toast(context, 'That does not look like a Spotify URL');
      return;
    }
    try {
      await auth.updateSpotifyProfileUrl(trimmed);
      if (context.mounted) _toast(context, 'Spotify URL updated');
    } catch (e) {
      if (context.mounted) _toast(context, '$e');
    }
  }

  /// Opens the edit dialog and returns the typed text, or null if cancelled.
  ///
  /// The [TextEditingController] is created and disposed *by the dialog* rather
  /// than by the caller. `showDialog`'s future completes as soon as the route is
  /// popped, but the reverse transition keeps the `TextField` mounted for a few
  /// more frames - so disposing the controller from the caller disposed it while
  /// `EditableText` was still a dependent, which threw
  /// `dependents.isEmpty: is not true` on every save. Letting the dialog own the
  /// controller ties its lifetime to the widget that actually uses it.
  Future<String?> _prompt(
    BuildContext context, {
    required String title,
    required String hint,
    required String initial,
    required String confirmLabel,
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => _EditTextDialog(
        title: title,
        hint: hint,
        initial: initial,
        confirmLabel: confirmLabel,
      ),
    );
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Stateful so it can own and dispose its [TextEditingController] at exactly the
/// right moment - when its `TextField` goes away, not a frame earlier or later.
class _EditTextDialog extends StatefulWidget {
  final String title;
  final String hint;
  final String initial;
  final String confirmLabel;

  const _EditTextDialog({
    required this.title,
    required this.hint,
    required this.initial,
    required this.confirmLabel,
  });

  @override
  State<_EditTextDialog> createState() => _EditTextDialogState();
}

class _EditTextDialogState extends State<_EditTextDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: SpotterfyTheme.surface,
      title: Text(widget.title, style: TextStyle(color: SpotterfyTheme.text)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 1,
        style: TextStyle(color: SpotterfyTheme.text),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: TextStyle(color: SpotterfyTheme.muted),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: SpotterfyTheme.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(
            widget.confirmLabel,
            style: TextStyle(color: SpotterfyTheme.primary),
          ),
        ),
      ],
    );
  }
}
