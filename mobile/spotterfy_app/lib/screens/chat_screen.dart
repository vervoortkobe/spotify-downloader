import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/social_provider.dart';
import 'package:spotterfy_app/services/polling_service.dart';
import 'package:spotterfy_app/services/social_service.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/app_background.dart';
import 'package:spotterfy_app/widgets/app_chrome.dart';
import 'package:spotterfy_app/widgets/presence_avatar.dart';

/// One-to-one conversation with a friend.
///
/// The transcript is refreshed by polling rather than a live Firestore
/// listener, so a dropped connection or a missing index cannot leave the thread
/// frozen. Sending a message also kicks the poll so the sender sees it
/// immediately instead of waiting out the interval.
class ChatScreen extends StatefulWidget {
  final SocialUser peer;

  const ChatScreen({super.key, required this.peer});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  /// Pulses the conversation poll right after we send, so our own message shows
  /// up without waiting for the next tick.
  final _refresh = StreamController<void>.broadcast();

  late String _myUid;
  late String _chatId;
  late Stream<List<ChatMessage>> _messages;
  StreamSubscription<List<ChatMessage>>? _messagesSub;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _myUid = context.read<SocialProvider>().uid ?? '';
    _chatId = SocialService.chatIdFor(_myUid, widget.peer.uid);
    _messages = PollingService.instance.poll<List<ChatMessage>>(
      fetch: () => SocialService.instance.messagesOnce(_chatId),
      interval: PollingService.chatInterval,
      signature: (list) => '${list.length}:${list.isEmpty ? '' : list.last.id}',
      refresh: _refresh.stream,
    );
    _messagesSub = _messages.listen((_) => _scrollToBottomIfNear());
  }

  @override
  void dispose() {
    _messagesSub?.cancel();
    _refresh.close();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final auth = context.read<AuthProvider>();
    final social = context.read<SocialProvider>();
    _controller.clear();
    await social.sendMessage(
      myName: auth.user?.displayName ?? 'Me',
      myPhoto: auth.user?.photoUrl ?? '',
      peer: widget.peer,
      text: text,
    );
    if (!mounted) return;
    _refresh.add(null);
    _scrollToBottom();
  }

  /// Jumps to the newest message after sending, once the list has grown.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  /// Keeps the newest message visible as it arrives, but does not yank a user
  /// who has scrolled up to read history back to the bottom.
  void _scrollToBottomIfNear() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      final atBottom =
          position.maxScrollExtent - position.pixels < 120 ||
          position.maxScrollExtent == 0;
      if (atBottom) _scroll.jumpTo(position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final myUid = _myUid;
    // A conversation fills the screen like the settings pages; the mini player
    // would otherwise float over the composer and the newest messages.
    return HideAppChrome(
      child: AppGradientScaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          titleSpacing: 0,
          title: Row(
            children: [
              PresenceAvatar(uid: widget.peer.uid, photoUrl: widget.peer.photoUrl, radius: 17),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  widget.peer.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: SpotterfyTheme.text,
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
                stream: _messages,
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
                              color: mine ? Colors.black : SpotterfyTheme.text,
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
      decoration: BoxDecoration(
        color: SpotterfyTheme.fill,
        border: Border(top: BorderSide(color: SpotterfyTheme.borderColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              style: TextStyle(color: SpotterfyTheme.text, fontSize: 14),
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
