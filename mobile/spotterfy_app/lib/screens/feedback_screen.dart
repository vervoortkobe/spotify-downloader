import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/services/feedback_service.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/app_background.dart';
import 'package:spotterfy_app/widgets/app_chrome.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your feedback first')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final user = context.read<AuthProvider>().user;
      await FeedbackService().submitFeedback(
        message: text,
        user: user,
      );
      if (!mounted) return;
      setState(() => _sending = false);
      _controller.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Thank you! Your feedback has been sent.'),
          backgroundColor: SpotterfyTheme.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send feedback: $e'),
          backgroundColor: const Color(0xFFef4444),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return HideAppChrome(
      child: AppGradientScaffold(
        title: 'Send Feedback',
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('We\'d love to hear from you'),
              _textCard(
                'Whether you have a feature request, found a bug, or just want to say hi — let us know!',
              ),
              const SizedBox(height: 24),
              _sectionTitle('Your feedback'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: SpotterfyTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextField(
                  controller: _controller,
                  maxLines: 6,
                  style: TextStyle(color: SpotterfyTheme.text, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Type your feedback here…',
                    hintStyle: TextStyle(color: SpotterfyTheme.muted),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: _sending ? null : _send,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            SpotterfyTheme.primary.withValues(alpha: 0.12),
                            SpotterfyTheme.primary.withValues(alpha: 0.04),
                          ],
                        ),
                        border: Border.all(
                          color: SpotterfyTheme.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _sending
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: SpotterfyTheme.primary,
                                  ),
                                )
                              : Icon(
                                  Icons.send_rounded,
                                  size: 20,
                                  color: SpotterfyTheme.primary,
                                ),
                          const SizedBox(width: 10),
                          Text(
                            _sending ? 'Sending…' : 'Send feedback',
                            style: TextStyle(
                              color: SpotterfyTheme.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
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

  Widget _textCard(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: SpotterfyTheme.surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: SpotterfyTheme.text,
        fontSize: 14,
        height: 1.5,
      ),
    ),
  );
}