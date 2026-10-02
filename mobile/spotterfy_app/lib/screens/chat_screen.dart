import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/social_provider.dart';
import 'package:spotterfy_app/services/social_service.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/app_background.dart';

/// One-to-one conversation with a friend.
class ChatScreen extends StatefulWidget {
  final SocialUser peer;

  const ChatScreen({super.key, required this.peer});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _chatId => SocialService.chatIdFor(
    context.read<SocialProvider>().uid ?? '',
    widget.peer.uid,
  );

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final auth = context.read<AuthProvider>();
    final social = context.read<SocialProvider>();
    _controller.clear();
    social.sendMessage(
      myName: auth.user?.displayName ?? 'Me',
      myPhoto: auth.user?.photoUrl ?? '',
      peer: widget.peer,
      text: text,
    );
    // Jump to the newest message once the list has grown.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final myUid = context.read<SocialProvider>().uid ?? '';
    return AppGradientScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: SpotterfyTheme.surface,
              backgroundImage: widget.peer.photoUrl.isNotEmpty
                  ? NetworkImage(widget.peer.photoUrl)
                  : null,
              child: widget.peer.photoUrl.isEmpty
                  ? Icon(Icons.person, color: SpotterfyTheme.muted, size: 18)
                  : null,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                widget.peer.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: SocialService.instance.messagesStream(_chatId),
              builder: (context, snap) {
                final messages = snap.data ?? const <ChatMessage>[];
                if (messages.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No messages yet. Say hello!',
                        style: TextStyle(color: SpotterfyTheme.muted),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final m = messages[i];
                    final mine = m.senderUid == myUid;
                    return Align(
                      alignment: mine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        constraints: const BoxConstraints(maxWidth: 280),
                        decoration: BoxDecoration(
                          color: mine
                              ? SpotterfyTheme.primary
                              : SpotterfyTheme.surface,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(mine ? 16 : 4),
                            bottomRight: Radius.circular(mine ? 4 : 16),
                          ),
                        ),
                        child: Text(
                          m.text,
                          style: TextStyle(
                            color: mine ? Colors.black : Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          _composer(),
        ],
      ),
    );
  }

  Widget _composer() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        8 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0a1410),
        border: Border(top: BorderSide(color: Color(0xFF1a3a2a))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Message',
                hintStyle: TextStyle(color: SpotterfyTheme.muted),
                isDense: true,
                filled: true,
                fillColor: SpotterfyTheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: SpotterfyTheme.primary,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: _send,
              customBorder: const CircleBorder(),
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.send, color: Colors.black, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
