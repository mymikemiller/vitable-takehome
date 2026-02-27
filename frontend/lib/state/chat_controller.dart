import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../services/chat_api_service.dart';

/// Owns all Signals and business logic for the chat screen.
/// Instantiated once in main.dart and injected via constructors — no globals.
class ChatController {
  ChatController({required this.apiService}) : _sessionId = const Uuid().v4() {
    _showWelcomeMessage();
  }

  final ChatApiService apiService;
  final String _sessionId;
  final _random = Random();

  // ── Public Signals ─────────────────────────────────────────────────────────

  /// Full message list. Append-only in practice; rebuilt on each change.
  final messages = signal<List<ChatMessage>>([]);

  /// True while waiting for server response OR during character animation.
  /// Input and send button are disabled when true.
  final isSending = signal<bool>(false);

  /// True when the 650ms reading delay has elapsed and server hasn't responded.
  /// Controls typing indicator visibility.
  final isTyping = signal<bool>(false);

  /// ID of the message currently being character-animated. Null when idle.
  final animatingMessageId = signal<String?>(null);

  /// The animated text content for the message being animated.
  /// Grows one character at a time during animation.
  final animatingText = signal<String>('');

  // ── Private State ──────────────────────────────────────────────────────────

  CancelToken? _cancelToken;
  Timer? _readingDelayTimer;
  String? _lastUserMessageText; // retained for retry

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Called by UI when user taps Send or presses Enter.
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || isSending.value) return;

    _lastUserMessageText = trimmed;
    await _dispatchMessage(trimmed);
  }

  /// Called when user taps an error bubble to retry the last failed message.
  Future<void> retryLastMessage() async {
    if (isSending.value) return;
    final last = _lastUserMessageText;
    if (last == null) return;

    // Remove the error bubble.
    final current = List<ChatMessage>.from(messages.value);
    if (current.isNotEmpty && current.last.isError) {
      current.removeLast();
      messages.value = current;
    }

    await _dispatchMessage(last);
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  /// Animates a greeting on first load without making a network request.
  Future<void> _showWelcomeMessage() async {
    const welcome =
        "Hello! I'm the Vitable Health virtual scheduling assistant. "
        "What brings you in today? I can help you schedule an appointment.";

    final msgId = const Uuid().v4();
    isSending.value = true;
    _appendMessage(ChatMessage(
      id: msgId,
      text: '',
      isUser: false,
      timestamp: DateTime.now(),
    ));
    await _animateMessage(msgId, welcome);
  }

  Future<void> _dispatchMessage(String text) async {
    // 1. Append user message immediately.
    _appendMessage(ChatMessage(
      id: const Uuid().v4(),
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    ));

    // 2. Disable input immediately — user cannot send during request + animation.
    isSending.value = true;

    // 3. Start two parallel operations:
    //    a) 650ms "reading delay" timer — shows typing indicator if server is slow.
    //    b) Network request — fires immediately.
    _cancelToken = CancelToken();
    bool responseReceived = false;
    ChatApiResponse? apiResponse;
    Object? apiError;

    // 3a. Reading delay: if server hasn't responded after 650ms, show typing indicator.
    _readingDelayTimer = Timer(const Duration(milliseconds: 650), () {
      if (!responseReceived) {
        isTyping.value = true;
      }
    });

    // 3b. Fire the network request.
    try {
      apiResponse = await apiService.sendMessage(
        sessionId: _sessionId,
        message: text,
        cancelToken: _cancelToken!,
      );
    } on DioException catch (e) {
      if (!CancelToken.isCancel(e)) {
        apiError = e;
      }
    } catch (e) {
      apiError = e;
    }

    responseReceived = true;
    _readingDelayTimer?.cancel();
    _readingDelayTimer = null;

    // 4. Hide typing indicator regardless of outcome.
    isTyping.value = false;

    if (apiError != null) {
      // Network or server error: insert error bubble, re-enable input.
      _appendError();
      isSending.value = false;
      return;
    }

    if (apiResponse != null) {
      // 5. Insert AI message with empty text (bubble appears immediately).
      final msgId = const Uuid().v4();
      _appendMessage(ChatMessage(
        id: msgId,
        text: '',
        isUser: false,
        timestamp: DateTime.now(),
        calendarEvent: apiResponse.calendarEvent,
      ));

      // 6. Animate text character by character.
      await _animateMessage(msgId, apiResponse.assistantMessage);
    }
  }

  /// Animates [fullText] into the message with [msgId], character by character.
  /// Uses 17ms base + 0–8ms random jitter per character.
  Future<void> _animateMessage(String msgId, String fullText) async {
    animatingMessageId.value = msgId;
    animatingText.value = '';

    for (int i = 0; i < fullText.length; i++) {
      // 17ms base + 0-8ms jitter = 17-25ms per character.
      final delay = 17 + _random.nextInt(9);
      await Future.delayed(Duration(milliseconds: delay));
      animatingText.value = fullText.substring(0, i + 1);
    }

    // Animation complete: update the stored message with full text.
    _updateMessageText(msgId, fullText);

    // Clear animation state — triggers MessageBubble to switch to static render.
    animatingMessageId.value = null;
    animatingText.value = '';

    // Re-enable input now that animation is complete.
    isSending.value = false;
  }

  void _appendMessage(ChatMessage msg) {
    messages.value = [...messages.value, msg];
  }

  void _appendError() {
    _appendMessage(ChatMessage(
      id: const Uuid().v4(),
      text: 'Something went wrong. Tap to retry.',
      isUser: false,
      timestamp: DateTime.now(),
      isError: true,
    ));
  }

  /// Updates the stored text of a message in-place (used after animation completes).
  void _updateMessageText(String id, String text) {
    messages.value = [
      for (final m in messages.value)
        if (m.id == id) m.copyWith(text: text) else m,
    ];
  }

  /// Clean up timers and cancel any in-flight request.
  void dispose() {
    _cancelToken?.cancel();
    _readingDelayTimer?.cancel();
  }
}
