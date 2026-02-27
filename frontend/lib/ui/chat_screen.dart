import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';
import '../state/chat_controller.dart';
import '../theme/app_theme.dart';
import 'message_bubble.dart';
import 'typing_indicator.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.controller});

  final ChatController controller;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  // EffectCleanup = void Function() — store to dispose subscriptions.
  final List<EffectCleanup> _cleanups = [];

  @override
  void initState() {
    super.initState();

    // Scroll to bottom whenever messages list changes (new message added).
    _cleanups.add(effect(() {
      widget.controller.messages.value; // subscribe
      _scheduleScrollToBottom();
    }));

    // Scroll on every animation character step.
    _cleanups.add(effect(() {
      widget.controller.animatingText.value; // subscribe
      _scheduleScrollToBottom();
    }));

    // Scroll when typing indicator appears or disappears.
    _cleanups.add(effect(() {
      widget.controller.isTyping.value; // subscribe
      _scheduleScrollToBottom();
    }));

    // Focus the input field once the AI finishes animating its response.
    _cleanups.add(effect(() {
      if (!widget.controller.isSending.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusNode.requestFocus();
        });
      }
    }));
  }

  @override
  void dispose() {
    // Call each cleanup to unsubscribe effects.
    for (final cleanup in _cleanups) {
      cleanup();
    }
    _textController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _onSend() async {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    _textController.clear();
    await widget.controller.sendMessage(text);
    _focusNode.requestFocus();
  }

  /// Enter = send (when not locked). Shift/Cmd/Ctrl + Enter = newline.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      final shift = HardwareKeyboard.instance.isShiftPressed;
      final meta = HardwareKeyboard.instance.isMetaPressed;
      final ctrl = HardwareKeyboard.instance.isControlPressed;

      if (shift || meta || ctrl) {
        // Insert newline at cursor position.
        final sel = _textController.selection;
        final text = _textController.text;
        final newText = text.replaceRange(
          sel.start.clamp(0, text.length),
          sel.end.clamp(0, text.length),
          '\n',
        );
        _textController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(
            offset: sel.start.clamp(0, text.length) + 1,
          ),
        );
        return KeyEventResult.handled;
      }

      // Plain Enter: send only if not currently locked.
      if (!widget.controller.isSending.value) {
        _onSend();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        backgroundColor: AppTheme.outerBg,
        body: Center(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: AppTheme.maxChatColumnWidth),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: AppTheme.chatBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.webWindowBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 32,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _ChatContent(
                  controller: widget.controller,
                  textController: _textController,
                  focusNode: _focusNode,
                  scrollController: _scrollController,
                  onSend: _onSend,
                  onKeyEvent: _handleKeyEvent,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Mobile: edge-to-edge, safe areas handled by Scaffold + SafeArea.
    return Scaffold(
      backgroundColor: AppTheme.chatBg,
      body: SafeArea(
        child: _ChatContent(
          controller: widget.controller,
          textController: _textController,
          focusNode: _focusNode,
          scrollController: _scrollController,
          onSend: _onSend,
          onKeyEvent: _handleKeyEvent,
        ),
      ),
    );
  }
}

// ── _ChatContent ──────────────────────────────────────────────────────────────

/// The inner chat column: app bar + message list + input bar.
/// Extracted so it can be reused for both web (inside container) and mobile.
class _ChatContent extends StatelessWidget {
  const _ChatContent({
    required this.controller,
    required this.textController,
    required this.focusNode,
    required this.scrollController,
    required this.onSend,
    required this.onKeyEvent,
  });

  final ChatController controller;
  final TextEditingController textController;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final VoidCallback onSend;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _AppBar(),
        Expanded(
          child: _MessageList(
            controller: controller,
            scrollController: scrollController,
          ),
        ),
        _InputBar(
          controller: controller,
          textController: textController,
          focusNode: focusNode,
          onSend: onSend,
          onKeyEvent: onKeyEvent,
        ),
      ],
    );
  }
}

// ── App Bar ───────────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: AppTheme.aiBubbleBg,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.userBubbleBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.local_hospital,
              color: AppTheme.aiBubbleBg,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vitable Health',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              Text(
                'Scheduling Assistant',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Message List ──────────────────────────────────────────────────────────────

/// The scrollable message list.
///
/// Performance: this Watch rebuilds when [messages] or [animatingMessageId]
/// changes (new message, animation start/end — rare events).
/// Per-character rebuilds happen ONLY inside the MessageBubble's inner Watch.
class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.controller,
    required this.scrollController,
  });

  final ChatController controller;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final messages = controller.messages.value;
      final animatingId = controller.animatingMessageId.value;
      final isTyping = controller.isTyping.value;

      final itemCount = messages.length + (isTyping ? 1 : 0);

      return ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          // Typing indicator is appended as the last item.
          if (isTyping && index == itemCount - 1) {
            return const TypingIndicator();
          }

          final message = messages[index];
          final isAnimating = message.id == animatingId;

          return MessageBubble(
            key: ValueKey(message.id),
            message: message,
            controller: controller,
            animatingTextSignal: isAnimating ? controller.animatingText : null,
          );
        },
      );
    });
  }
}

// ── Input Bar ─────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.textController,
    required this.focusNode,
    required this.onSend,
    required this.onKeyEvent,
  });

  final ChatController controller;
  final TextEditingController textController;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final isSending = controller.isSending.value;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: AppTheme.chatBg,
          border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Focus(
                onKeyEvent: onKeyEvent,
                child: TextField(
                  controller: textController,
                  focusNode: focusNode,
                  enabled: !isSending,
                  maxLines: 6,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  style: AppTheme.inputTextStyle,
                  decoration: InputDecoration(
                    hintText: isSending
                        ? 'Waiting for response\u2026'
                        : 'Type a message\u2026',
                    hintStyle: const TextStyle(color: AppTheme.inputHint),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: AppTheme.inputBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: AppTheme.inputBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide:
                          const BorderSide(color: AppTheme.aiBubbleBg),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: AppTheme.inputBorderDisabled),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    filled: true,
                    fillColor: isSending
                        ? AppTheme.inputBgDisabled
                        : Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _SendButton(isSending: isSending, onSend: onSend),
          ],
        ),
      );
    });
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.isSending, required this.onSend});

  final bool isSending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: isSending
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: isSending ? null : onSend,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isSending ? AppTheme.sendButtonDisabled : AppTheme.aiBubbleBg,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.send_rounded,
            color: isSending ? AppTheme.sendButtonIconDisabled : Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}
