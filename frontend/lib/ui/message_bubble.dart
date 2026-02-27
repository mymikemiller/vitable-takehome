import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import '../models/chat_message.dart';
import '../state/chat_controller.dart';
import '../theme/app_theme.dart';
import 'calendar_buttons.dart';

/// Renders a single chat message bubble.
///
/// Performance contract:
///   - If [animatingTextSignal] is null, this widget is entirely static.
///   - If [animatingTextSignal] is non-null, ONLY the inner Text widget
///     rebuilds per character via Watch — the bubble container does not.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.controller,
    this.animatingTextSignal,
  });

  final ChatMessage message;
  final ChatController controller;

  /// Non-null only for the message currently being character-animated.
  final Signal<String>? animatingTextSignal;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: message.isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          _BubbleContainer(
            message: message,
            controller: controller,
            animatingTextSignal: animatingTextSignal,
          ),
          // Calendar buttons appear only after animation completes on confirmed appointments.
          if (!message.isUser &&
              !message.isError &&
              message.calendarEvent != null &&
              animatingTextSignal == null)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16),
              child: CalendarButtons(event: message.calendarEvent!),
            ),
        ],
      ),
    );
  }
}

// ── Bubble Container ──────────────────────────────────────────────────────────

class _BubbleContainer extends StatelessWidget {
  const _BubbleContainer({
    required this.message,
    required this.controller,
    this.animatingTextSignal,
  });

  final ChatMessage message;
  final ChatController controller;
  final Signal<String>? animatingTextSignal;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final isError = message.isError;

    final Color bg;
    if (isError) {
      bg = AppTheme.errorBubbleBg;
    } else if (isUser) {
      bg = AppTheme.userBubbleBg;
    } else {
      bg = AppTheme.aiBubbleBg;
    }

    const r = AppTheme.bubbleRadius;
    final borderRadius = isUser
        ? const BorderRadius.only(
            topLeft: Radius.circular(r),
            topRight: Radius.circular(r),
            bottomLeft: Radius.circular(r),
            bottomRight: Radius.circular(4),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(r),
            bottomLeft: Radius.circular(r),
            bottomRight: Radius.circular(r),
          );

    // Micro-scale animation: during animation bubble is 0.98 scale,
    // pops to 1.0 when animation completes (animatingTextSignal becomes null).
    final child = AnimatedScale(
      scale: animatingTextSignal != null ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width *
              AppTheme.maxBubbleWidthFraction,
        ),
        margin: EdgeInsets.only(
          left: isUser ? 60 : 16,
          right: isUser ? 16 : 60,
          top: 4,
          bottom: 4,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: bg, borderRadius: borderRadius),
        child: _BubbleText(
          message: message,
          animatingTextSignal: animatingTextSignal,
        ),
      ),
    );

    // Error bubbles are tappable for retry.
    if (isError) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: controller.retryLastMessage,
          child: child,
        ),
      );
    }
    return child;
  }
}

// ── Bubble Text ───────────────────────────────────────────────────────────────

/// Text content of a bubble.
///
/// When [animatingTextSignal] is non-null: wrapped in Watch — only THIS widget
/// rebuilds per character.
/// When null: static SelectableText — zero rebuilds.
class _BubbleText extends StatelessWidget {
  const _BubbleText({
    required this.message,
    this.animatingTextSignal,
  });

  final ChatMessage message;
  final Signal<String>? animatingTextSignal;

  @override
  Widget build(BuildContext context) {
    final Color textColor;
    if (message.isError) {
      textColor = AppTheme.errorText;
    } else if (message.isUser) {
      textColor = AppTheme.userBubbleText;
    } else {
      textColor = AppTheme.aiMessageText;
    }

    final textStyle = AppTheme.bubbleTextStyle.copyWith(color: textColor);

    if (animatingTextSignal != null) {
      // Only this Watch widget rebuilds per character.
      return Watch((context) {
        final text = animatingTextSignal!.value;
        return _BlinkingCursorText(text: text, textStyle: textStyle);
      });
    }

    return SelectableText(message.text, style: textStyle);
  }
}

// ── Blinking Cursor Text ──────────────────────────────────────────────────────

/// Shows text with a blinking | cursor during animation.
/// The cursor blinks independently of the character animation.
class _BlinkingCursorText extends StatefulWidget {
  const _BlinkingCursorText({
    required this.text,
    required this.textStyle,
  });
  final String text;
  final TextStyle textStyle;

  @override
  State<_BlinkingCursorText> createState() => _BlinkingCursorTextState();
}

class _BlinkingCursorTextState extends State<_BlinkingCursorText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _blink,
      builder: (context, _) {
        final cursor = _blink.value > 0.5 ? '|' : '';
        return SelectableText(
          widget.text + cursor,
          style: widget.textStyle,
        );
      },
    );
  }
}
