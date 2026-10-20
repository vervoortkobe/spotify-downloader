import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/social_provider.dart';
import 'package:spotterfy_app/services/feedback_service.dart';
import 'package:spotterfy_app/services/network_stats_service.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

/// Shown instead of the app when the signed-in account has been suspended.
class SuspendedScreen extends StatefulWidget {
  const SuspendedScreen({super.key});

  @override
  State<SuspendedScreen> createState() => _SuspendedScreenState();
}

class _SuspendedScreenState extends State<SuspendedScreen> {
  bool _sendingAppeal = false;

  Future<void> _submitAppeal() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _AppealDialog(),
    );
    if (reason == null || reason.isEmpty || !mounted) return;

    setState(() => _sendingAppeal = true);
    try {
      await FeedbackService().submitFeedback(
        message: reason,
        user: context.read<AuthProvider>().user,
        type: 'appeal',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your appeal has been sent.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send appeal: $e')),
      );
    } finally {
      if (mounted) setState(() => _sendingAppeal = false);
    }
  }

  Future<void> _signOut() async {
    final auth = context.read<AuthProvider>();
    await NetworkStatsService.instance?.setUserId(null);
    // Stop social listeners before the token is revoked.
    context.read<SocialProvider>().syncUid(null);
    await auth.signOut();
    // The splash screen is the auth gate and swaps this screen for LoginScreen.
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final reason = auth.suspendedReason.trim().isEmpty
        ? 'Breach of Terms and Conditions'
        : auth.suspendedReason.trim();

    return Scaffold(
      backgroundColor: SpotterfyTheme.pageBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: const Color(0xFFef4444).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.gpp_maybe,
                        color: Color(0xFFef4444),
                        size: 44,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Account suspended',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: SpotterfyTheme.text,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if ((auth.user?.email ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      auth.user!.email,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: SpotterfyTheme.mutedDark,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: SpotterfyTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: SpotterfyTheme.borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reason for suspension',
                          style: TextStyle(
                            color: SpotterfyTheme.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          reason,
                          style: TextStyle(
                            color: SpotterfyTheme.mutedDark,
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _sendingAppeal ? null : _submitAppeal,
                      icon: _sendingAppeal
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.rate_review_outlined),
                      label: Text(
                        _sendingAppeal ? 'Sending...' : 'Submit an appeal',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: SpotterfyTheme.primary,
                        foregroundColor: SpotterfyTheme.onAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: _signOut,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: SpotterfyTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.logout, color: Colors.red, size: 20),
                          SizedBox(width: 12),
                          Text(
                            'Sign Out',
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Spacer(),
                          Icon(Icons.chevron_right, color: Colors.red, size: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppealDialog extends StatefulWidget {
  const _AppealDialog();

  @override
  State<_AppealDialog> createState() => _AppealDialogState();
}

class _AppealDialogState extends State<_AppealDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: SpotterfyTheme.surface,
      title: Text('Submit an appeal', style: TextStyle(color: SpotterfyTheme.text)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        style: TextStyle(color: SpotterfyTheme.text),
        decoration: InputDecoration(
          hintText: 'Explain why you think the suspension should be reviewed',
          hintStyle: TextStyle(color: SpotterfyTheme.mutedDark),
          errorText: _error,
          filled: true,
          fillColor: SpotterfyTheme.pageBackground,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: SpotterfyTheme.muted)),
        ),
        TextButton(
          onPressed: () {
            final appeal = _controller.text.trim();
            if (appeal.isEmpty) {
              setState(() => _error = 'Please enter a reason for your appeal.');
              return;
            }
            Navigator.pop(context, appeal);
          },
          child: Text(
            'Send',
            style: TextStyle(color: SpotterfyTheme.primary, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
