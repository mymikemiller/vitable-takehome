# Flutter Chat App Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a production-quality cross-platform (iOS/Android/Web) Flutter scheduling chat app for Vitable Health.

**Architecture:** Signals-based state in ChatController injected via constructors; stateless ChatApiService handles Dio; UI layer has zero business logic. Character animation scoped to a single Watch widget per message to maintain 60fps.

**Tech Stack:** Flutter 3.x, signals_flutter ^0.6, dio ^5.7, url_launcher ^6.3, uuid ^4.5, path_provider ^2.1, share_plus ^10.0

---

### Task 1: Initialize Flutter project

**Files:**
- Create: `pubspec.yaml` (via flutter create + edit)
- Create: `lib/main.dart` (scaffold only)

**Step 1: Create Flutter project**

```bash
flutter create --org com.vitablehealth --project-name vitable_chat .
```

Expected: Flutter project scaffolded in current directory.

**Step 2: Replace pubspec.yaml**

Replace the generated pubspec.yaml with:

```yaml
name: vitable_chat
description: Vitable Health Scheduling Chat
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

  # State management
  signals_flutter: ^0.6.3

  # Networking
  dio: ^5.7.0

  # URL launching (Google Calendar, Apple Calendar web)
  url_launcher: ^6.3.1

  # Session ID generation
  uuid: ^4.5.1

  # Mobile ICS file handling
  path_provider: ^2.1.5
  share_plus: ^10.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true
```

**Step 3: Get dependencies**

```bash
flutter pub get
```

Expected: All packages resolve without conflict.

---

### Task 2: Theme — `lib/theme/app_theme.dart`

**Files:**
- Create: `lib/theme/app_theme.dart`

**Step 1: Write theme file**

```dart
import 'package:flutter/material.dart';

/// Central theme configuration for Vitable Health chat app.
/// All color literals live here — never scatter them across the UI layer.
abstract final class AppTheme {
  // ── Brand Colors ──────────────────────────────────────────────────────────

  /// User message bubble background (Vitable green tint)
  static const Color userBubbleBg = Color(0xFFBFF4C8);

  /// User message text
  static const Color userBubbleText = Color(0xFF003C32);

  /// AI message bubble background (Vitable dark green)
  static const Color aiBubbleBg = Color(0xFF003C32);

  /// AI message text
  static const Color aiMessageText = Colors.white;

  /// Accent / button color
  static const Color accent = Color(0xFF3C6DD8);

  /// Secondary accent (calendar buttons)
  static const Color accentSecondary = Color(0xFF682C46);

  /// White background inside chat container
  static const Color chatBg = Colors.white;

  /// Dark outer page background (web only)
  static const Color outerBg = Color(0xFF1E1E1E);

  /// Error bubble background
  static const Color errorBubbleBg = Color(0xFFFFEDED);

  /// Error text
  static const Color errorText = Color(0xFF9B1C1C);

  // ── Layout ────────────────────────────────────────────────────────────────

  /// Maximum width for bubble content
  static const double maxBubbleWidthFraction = 0.80;

  /// Maximum width for the centered chat column on web
  static const double maxChatColumnWidth = 860.0;

  /// Bubble border radius
  static const double bubbleRadius = 16.0;

  // ── Typography ────────────────────────────────────────────────────────────

  static const TextStyle bubbleTextStyle = TextStyle(
    fontSize: 15.0,
    height: 1.45,
  );

  static const TextStyle inputTextStyle = TextStyle(
    fontSize: 15.0,
  );

  // ── Material Theme ────────────────────────────────────────────────────────

  static ThemeData get lightTheme => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: aiBubbleBg,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: chatBg,
        fontFamily: 'SF Pro Text',
        useMaterial3: true,
      );
}
```

---

### Task 3: Message Model — `lib/models/chat_message.dart`

**Files:**
- Create: `lib/models/chat_message.dart`

**Step 1: Write immutable model**

```dart
import 'package:flutter/foundation.dart';

/// Immutable data class for a single chat turn.
///
/// [calendarEvent] is non-null only on the assistant message that
/// the backend returns after a confirmed appointment booking.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isError = false,
    this.calendarEvent,
  });

  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isError;
  final CalendarEvent? calendarEvent;

  ChatMessage copyWith({String? text, bool? isError}) => ChatMessage(
        id: id,
        text: text ?? this.text,
        isUser: isUser,
        timestamp: timestamp,
        isError: isError ?? this.isError,
        calendarEvent: calendarEvent,
      );
}

/// Structured calendar event returned by the backend after booking.
/// start_iso and end_iso are ISO 8601 UTC strings.
@immutable
class CalendarEvent {
  const CalendarEvent({
    required this.title,
    required this.startIso,
    required this.endIso,
    required this.description,
    this.location,
  });

  final String title;
  final String startIso;
  final String endIso;
  final String description;
  final String? location;

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
        title: json['title'] as String,
        startIso: json['start_iso'] as String,
        endIso: json['end_iso'] as String,
        description: json['description'] as String,
        location: json['location'] as String?,
      );
}
```

---

### Task 4: API Service — `lib/services/chat_api_service.dart`

**Files:**
- Create: `lib/services/chat_api_service.dart`

**Step 1: Write stateless service**

The service wraps Dio. It is stateless — ChatController owns the session ID and cancel tokens.

```dart
import 'package:dio/dio.dart';
import '../models/chat_message.dart';

/// Response DTO from POST /chat.
class ChatApiResponse {
  const ChatApiResponse({
    required this.assistantMessage,
    this.calendarEvent,
  });
  final String assistantMessage;
  final CalendarEvent? calendarEvent;
}

/// Stateless API client. Business logic lives in ChatController.
class ChatApiService {
  ChatApiService({required String baseUrl})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            headers: {'Content-Type': 'application/json'},
          ),
        );

  final Dio _dio;

  /// POST /chat. Throws DioException on network/server error.
  Future<ChatApiResponse> sendMessage({
    required String sessionId,
    required String message,
    required CancelToken cancelToken,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/chat',
      data: {'session_id': sessionId, 'message': message},
      cancelToken: cancelToken,
    );

    final data = response.data!;
    final rawEvent = data['calendar_event'];

    return ChatApiResponse(
      assistantMessage: data['assistant_message'] as String,
      calendarEvent: rawEvent != null
          ? CalendarEvent.fromJson(rawEvent as Map<String, dynamic>)
          : null,
    );
  }
}
```

---

### Task 5: ICS Platform Stub — `lib/services/ics_downloader.dart` (3 files)

This uses Flutter's conditional export pattern to dispatch ICS download to
platform-specific implementations without `dart:html` polluting mobile builds.

**Files:**
- Create: `lib/services/ics_downloader.dart` (selector)
- Create: `lib/services/ics_downloader_web.dart`
- Create: `lib/services/ics_downloader_mobile.dart`

**Step 1: Write selector**

`lib/services/ics_downloader.dart`:
```dart
export 'ics_downloader_mobile.dart'
    if (dart.library.html) 'ics_downloader_web.dart';
```

**Step 2: Write web implementation**

`lib/services/ics_downloader_web.dart`:
```dart
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Downloads an ICS file in the browser using a Blob URL.
void downloadIcs(String icsContent, String filename) {
  final blob = html.Blob([icsContent], 'text/calendar');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
```

**Step 3: Write mobile implementation**

`lib/services/ics_downloader_mobile.dart`:
```dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Saves ICS to a temp file and opens the share sheet on mobile.
Future<void> downloadIcs(String icsContent, String filename) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsString(icsContent);
  await Share.shareXFiles([XFile(file.path, mimeType: 'text/calendar')]);
}
```

---

### Task 6: Chat Controller — `lib/state/chat_controller.dart`

**Files:**
- Create: `lib/state/chat_controller.dart`

**Step 1: Write controller**

This is the most complex file. It owns all Signals and all business logic.

```dart
import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../services/chat_api_service.dart';

/// Owns all signals and business logic for the chat screen.
/// Injected via constructor — no global singletons.
class ChatController {
  ChatController({required this.apiService}) : _sessionId = const Uuid().v4();

  final ChatApiService apiService;
  final String _sessionId;
  final _random = Random();

  // ── Public Signals ─────────────────────────────────────────────────────────

  /// Full message list. UI subscribes to this for list rendering.
  late final messages = signal<List<ChatMessage>>([]);

  /// True while waiting for server response OR during character animation.
  late final isSending = signal<bool>(false);

  /// True when the 650ms reading delay has expired and response hasn't arrived.
  late final isTyping = signal<bool>(false);

  /// The message ID currently being animated (null = none).
  late final animatingMessageId = signal<String?>(null);

  /// Current animated text for the animating message.
  late final animatingText = signal<String>('');

  // ── Private State ──────────────────────────────────────────────────────────

  CancelToken? _cancelToken;
  Timer? _readingDelayTimer;
  String? _lastUserMessageText; // for retry

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Called by UI when user taps Send or presses Enter.
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || isSending.value) return;

    _lastUserMessageText = trimmed;
    await _dispatchMessage(trimmed);
  }

  /// Called when user taps an error bubble to retry.
  Future<void> retryLastMessage() async {
    final last = _lastUserMessageText;
    if (last == null) return;

    // Remove the error bubble from the end of the list.
    final current = List<ChatMessage>.from(messages.value);
    if (current.isNotEmpty && current.last.isError) {
      current.removeLast();
      messages.value = current;
    }

    await _dispatchMessage(last);
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  Future<void> _dispatchMessage(String text) async {
    // 1. Append user message immediately.
    _appendMessage(ChatMessage(
      id: const Uuid().v4(),
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    ));

    // 2. Disable input.
    isSending.value = true;

    // 3. Start parallel: 650ms reading delay + network request.
    _cancelToken = CancelToken();
    bool responseReceived = false;
    ChatApiResponse? apiResponse;
    Object? apiError;

    // 3a. Reading delay: after 650ms, show typing indicator if still waiting.
    _readingDelayTimer = Timer(const Duration(milliseconds: 650), () {
      if (!responseReceived) {
        isTyping.value = true;
      }
    });

    // 3b. Fire network request.
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

    // 4. Hide typing indicator.
    isTyping.value = false;

    if (apiError != null) {
      _appendError();
      isSending.value = false;
      return;
    }

    if (apiResponse != null) {
      // 5. Insert AI message bubble (empty text initially).
      final msgId = const Uuid().v4();
      final aiMessage = ChatMessage(
        id: msgId,
        text: '',
        isUser: false,
        timestamp: DateTime.now(),
        calendarEvent: apiResponse.calendarEvent,
      );
      _appendMessage(aiMessage);

      // 6. Animate text character by character.
      await _animateMessage(msgId, apiResponse.assistantMessage);
    }
  }

  /// Animates [fullText] into the message identified by [msgId].
  Future<void> _animateMessage(String msgId, String fullText) async {
    animatingMessageId.value = msgId;
    animatingText.value = '';

    for (int i = 0; i < fullText.length; i++) {
      final delay = 17 + _random.nextInt(9); // 17–25ms per character
      await Future.delayed(Duration(milliseconds: delay));

      animatingText.value = fullText.substring(0, i + 1);
    }

    // Animation complete: update the message with full text, clear animation.
    _updateMessageText(msgId, fullText);
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

  void _updateMessageText(String id, String text) {
    messages.value = [
      for (final m in messages.value)
        if (m.id == id) m.copyWith(text: text) else m,
    ];
  }

  void dispose() {
    _cancelToken?.cancel();
    _readingDelayTimer?.cancel();
  }
}
```

---

### Task 7: Typing Indicator — `lib/ui/typing_indicator.dart`

**Files:**
- Create: `lib/ui/typing_indicator.dart`

**Step 1: Write animated three-dot indicator**

```dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Animated three-dot "thinking" indicator shown while awaiting server response.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 16, right: 80, top: 4, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.aiBubbleBg,
          borderRadius: BorderRadius.circular(AppTheme.bubbleRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) => _Dot(controller: _controller, index: i)),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.controller, required this.index});

  final AnimationController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    // Each dot bounces with 200ms offset.
    final animation = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -6.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -6.0, end: 0.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 2),
    ]).animate(
      CurvedAnimation(
        parent: controller,
        curve: Interval(index * 0.15, index * 0.15 + 0.55, curve: Curves.easeInOut),
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => Transform.translate(
        offset: Offset(0, animation.value),
        child: Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
```

---

### Task 8: Calendar Buttons — `lib/ui/calendar_buttons.dart`

**Files:**
- Create: `lib/ui/calendar_buttons.dart`

**Step 1: Write calendar button row**

Calendar buttons appear below an assistant bubble when `calendarEvent` is non-null.
Google Calendar uses a URL; Apple Calendar generates a .ics file.

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chat_message.dart';
import '../services/ics_downloader.dart';
import '../theme/app_theme.dart';

class CalendarButtons extends StatelessWidget {
  const CalendarButtons({super.key, required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CalButton(
            label: 'Add to Google Calendar',
            color: AppTheme.accent,
            onTap: _openGoogleCalendar,
          ),
          const SizedBox(width: 8),
          _CalButton(
            label: 'Add to Apple Calendar',
            color: AppTheme.accentSecondary,
            onTap: _downloadIcs,
          ),
        ],
      ),
    );
  }

  // ── Google Calendar ────────────────────────────────────────────────────────

  Future<void> _openGoogleCalendar() async {
    DateTime? start;
    DateTime? end;

    try {
      start = DateTime.parse(event.startIso);
      end = DateTime.parse(event.endIso);
    } catch (_) {
      // If parsing fails, skip calendar buttons gracefully.
      return;
    }

    final fmt = _toGoogleDateFormat(start);
    final fmtEnd = _toGoogleDateFormat(end);

    final uri = Uri.https('calendar.google.com', '/calendar/render', {
      'action': 'TEMPLATE',
      'text': event.title,
      'dates': '$fmt/$fmtEnd',
      'details': event.description,
      'location': event.location ?? 'Vitable Health',
    });

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch Google Calendar URL');
    }
  }

  /// Converts DateTime to Google Calendar format: YYYYMMDDTHHMMSSZ
  String _toGoogleDateFormat(DateTime dt) {
    final utc = dt.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}'
        '${utc.month.toString().padLeft(2, '0')}'
        '${utc.day.toString().padLeft(2, '0')}'
        'T${utc.hour.toString().padLeft(2, '0')}'
        '${utc.minute.toString().padLeft(2, '0')}'
        '${utc.second.toString().padLeft(2, '0')}Z';
  }

  // ── Apple Calendar / ICS ──────────────────────────────────────────────────

  Future<void> _downloadIcs() async {
    DateTime? start;
    DateTime? end;

    try {
      start = DateTime.parse(event.startIso);
      end = DateTime.parse(event.endIso);
    } catch (_) {
      return;
    }

    final ics = _buildIcs(start, end);
    final filename = 'vitable_appointment.ics';

    if (kIsWeb) {
      downloadIcs(ics, filename);
    } else {
      await downloadIcs(ics, filename);
    }
  }

  String _buildIcs(DateTime start, DateTime end) {
    final stamp = _toIcsFormat(DateTime.now().toUtc());
    final dtStart = _toIcsFormat(start.toUtc());
    final dtEnd = _toIcsFormat(end.toUtc());
    final uid = '${DateTime.now().millisecondsSinceEpoch}@vitablehealth.com';

    return '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Vitable Health//Chat//EN
BEGIN:VEVENT
UID:$uid
DTSTAMP:$stamp
DTSTART:$dtStart
DTEND:$dtEnd
SUMMARY:${event.title}
DESCRIPTION:${event.description.replaceAll('\n', '\\n')}
LOCATION:${event.location ?? 'Vitable Health'}
END:VEVENT
END:VCALENDAR''';
  }

  String _toIcsFormat(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}'
        '${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}'
        'T${dt.hour.toString().padLeft(2, '0')}'
        '${dt.minute.toString().padLeft(2, '0')}'
        '${dt.second.toString().padLeft(2, '0')}Z';
  }
}

class _CalButton extends StatelessWidget {
  const _CalButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
```

---

### Task 9: Message Bubble — `lib/ui/message_bubble.dart`

**Files:**
- Create: `lib/ui/message_bubble.dart`

**Key design:** Each bubble is passed an optional `animatingTextSignal`. If non-null, the
text widget is wrapped in `Watch` — only this widget rebuilds per character.
All other bubbles are static widgets. This is what guarantees 60fps performance.

**Step 1: Write message bubble**

```dart
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
///     rebuilds per character via Watch.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.controller,
    this.animatingTextSignal,
  });

  final ChatMessage message;
  final ChatController controller;

  /// Non-null only for the message currently being animated.
  final Signal<String>? animatingTextSignal;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final isError = message.isError;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          _BubbleContainer(
            isUser: isUser,
            isError: isError,
            onTap: isError ? controller.retryLastMessage : null,
            child: _BubbleText(
              message: message,
              animatingTextSignal: animatingTextSignal,
            ),
          ),
          // Calendar buttons appear only on non-animating confirmed appointments.
          if (!isUser && !isError && message.calendarEvent != null && animatingTextSignal == null)
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
    required this.isUser,
    required this.isError,
    required this.child,
    this.onTap,
  });

  final bool isUser;
  final bool isError;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Color bg;
    if (isError) {
      bg = AppTheme.errorBubbleBg;
    } else if (isUser) {
      bg = AppTheme.userBubbleBg;
    } else {
      bg = AppTheme.aiBubbleBg;
    }

    final radius = AppTheme.bubbleRadius;
    final borderRadius = isUser
        ? BorderRadius.only(
            topLeft: Radius.circular(radius),
            topRight: Radius.circular(radius),
            bottomLeft: Radius.circular(radius),
            bottomRight: const Radius.circular(4),
          )
        : BorderRadius.only(
            topLeft: const Radius.circular(4),
            topRight: Radius.circular(radius),
            bottomLeft: Radius.circular(radius),
            bottomRight: Radius.circular(radius),
          );

    Widget container = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * AppTheme.maxBubbleWidthFraction,
      ),
      margin: EdgeInsets.only(
        left: isUser ? 60 : 16,
        right: isUser ? 16 : 60,
        top: 4,
        bottom: 4,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: borderRadius),
      child: child,
    );

    if (onTap != null) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: onTap, child: container),
      );
    }
    return container;
  }
}

// ── Bubble Text ───────────────────────────────────────────────────────────────

/// The text portion of a bubble.
/// When [animatingTextSignal] is set, wraps in Watch for per-character rebuilds.
/// Otherwise completely static.
class _BubbleText extends StatelessWidget {
  const _BubbleText({
    required this.message,
    this.animatingTextSignal,
  });

  final ChatMessage message;
  final Signal<String>? animatingTextSignal;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final isError = message.isError;

    Color textColor;
    if (isError) {
      textColor = AppTheme.errorText;
    } else if (isUser) {
      textColor = AppTheme.userBubbleText;
    } else {
      textColor = AppTheme.aiMessageText;
    }

    final textStyle = AppTheme.bubbleTextStyle.copyWith(color: textColor);

    if (animatingTextSignal != null) {
      return Watch((context) {
        final text = animatingTextSignal!.value;
        return _AnimatingText(text: text, textStyle: textStyle);
      });
    }

    return SelectableText(
      message.text,
      style: textStyle,
    );
  }
}

/// Text with blinking cursor during animation, micro-scale pop on completion.
class _AnimatingText extends StatelessWidget {
  const _AnimatingText({required this.text, required this.textStyle});

  final String text;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    // Show text + blinking cursor during animation.
    return _BlinkingCursorText(text: text, textStyle: textStyle);
  }
}

class _BlinkingCursorText extends StatefulWidget {
  const _BlinkingCursorText({required this.text, required this.textStyle});
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
```

---

### Task 10: Chat Screen — `lib/ui/chat_screen.dart`

**Files:**
- Create: `lib/ui/chat_screen.dart`

**This is the largest UI file. Key responsibilities:**
- Render message list with proper scoping of Watch
- Handle scroll-to-bottom on message/animation/typing changes
- Handle keyboard input (Enter = send, Shift+Enter = newline)
- Responsive web layout (centered column, dark outer bg)
- Input bar with send button

**Step 1: Write chat screen**

```dart
import 'dart:math';
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
  final _inputKey = GlobalKey();

  late final List<EffectCleanup> _cleanups;

  @override
  void initState() {
    super.initState();

    // Scroll to bottom whenever messages change.
    _cleanups = [
      effect(() {
        widget.controller.messages.value; // subscribe
        _scheduleScrollToBottom();
      }),
      // Scroll per animation step.
      effect(() {
        widget.controller.animatingText.value; // subscribe
        _scheduleScrollToBottom();
      }),
      // Scroll when typing indicator appears.
      effect(() {
        widget.controller.isTyping.value; // subscribe
        _scheduleScrollToBottom();
      }),
    ];
  }

  @override
  void dispose() {
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

  // ── Keyboard handler: Enter = send, Shift+Enter/Cmd+Enter = newline ────────
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      final shift = HardwareKeyboard.instance.isShiftPressed;
      final meta = HardwareKeyboard.instance.isMetaPressed;
      final ctrl = HardwareKeyboard.instance.isControlPressed;

      if (shift || meta || ctrl) {
        // Insert newline.
        final sel = _textController.selection;
        final text = _textController.text;
        final newText = text.replaceRange(sel.start, sel.end, '\n');
        _textController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: sel.start + 1),
        );
        return KeyEventResult.handled;
      }

      // Plain Enter: send (if not currently sending).
      if (!widget.controller.isSending.value) {
        _onSend();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // On web: dark outer bg with centered white chat column.
    // On mobile: full-screen white.
    if (kIsWeb) {
      return Scaffold(
        backgroundColor: AppTheme.outerBg,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppTheme.maxChatColumnWidth),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: AppTheme.chatBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
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

    // Mobile: edge-to-edge with safe areas handled by Scaffold.
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

/// The inner scrollable message list + input bar.
/// Extracted to avoid duplicating across web/mobile layouts.
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
        Expanded(child: _MessageList(
          controller: controller,
          scrollController: scrollController,
        )),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: AppTheme.aiBubbleBg,
        border: Border(bottom: BorderSide(color: Colors.white12)),
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
            child: const Icon(Icons.local_hospital, color: AppTheme.aiBubbleBg, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Vitable Health',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              Text('Scheduling Assistant',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Message List ──────────────────────────────────────────────────────────────

/// Renders the scrollable message list.
///
/// Performance: this Watch rebuilds when [messages] or [animatingMessageId]
/// changes (new message = rare). Per-character rebuilds happen ONLY inside
/// the MessageBubble's inner Watch widget.
class _MessageList extends StatelessWidget {
  const _MessageList({required this.controller, required this.scrollController});

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
          // Typing indicator is the last item when visible.
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
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: max(12.0, MediaQuery.of(context).viewInsets.bottom > 0 ? 12.0 : 0),
        ),
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
                    hintText: isSending ? 'Waiting for response…' : 'Type a message…',
                    hintStyle: const TextStyle(color: Color(0xFFAAAAAA)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: AppTheme.aiBubbleBg),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    filled: true,
                    fillColor: isSending ? const Color(0xFFF5F5F5) : Colors.white,
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
      cursor: isSending ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: isSending ? null : onSend,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isSending ? Colors.grey.shade300 : AppTheme.aiBubbleBg,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.send_rounded,
            color: isSending ? Colors.grey.shade500 : Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}
```

---

### Task 11: Main Entry Point — `lib/main.dart`

**Files:**
- Modify: `lib/main.dart`

**Step 1: Write main.dart**

```dart
import 'package:flutter/material.dart';
import 'services/chat_api_service.dart';
import 'state/chat_controller.dart';
import 'theme/app_theme.dart';
import 'ui/chat_screen.dart';

void main() {
  runApp(const VitableApp());
}

class VitableApp extends StatefulWidget {
  const VitableApp({super.key});

  @override
  State<VitableApp> createState() => _VitableAppState();
}

class _VitableAppState extends State<VitableApp> {
  // ChatController is instantiated once and injected via constructor.
  // No global singletons — testable and extensible.
  late final ChatController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ChatController(
      apiService: ChatApiService(
        // Replace with your backend URL.
        // For local dev: http://localhost:8000
        baseUrl: 'http://localhost:8000',
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vitable Health',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: ChatScreen(controller: _controller),
    );
  }
}
```

---

### Task 12: Android & Web Platform Configuration

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml` — add INTERNET permission + url_launcher queries
- Modify: `web/index.html` — no changes needed
- Create: `lib/ui/completion_animation.dart` — scale 0.98→1.0 on message completion

**Step 1: Android manifest**

Add to `<manifest>`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

Add inside `<queries>` block (required for url_launcher on Android 11+):
```xml
<queries>
  <intent>
    <action android:name="android.intent.action.VIEW" />
    <data android:scheme="https" />
  </intent>
</queries>
```

**Step 2: Verify web CORS**

The Flutter web app runs on a different origin than the backend.
The backend (FastAPI) must have CORS enabled. Add to `../backend/main.py` if missing:

```python
from fastapi.middleware.cors import CORSMiddleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["POST", "GET"],
    allow_headers=["*"],
)
```
(Do NOT modify the backend per spec — note this for local dev docs only.)

---

### Task 13: Completion Animation on Message Bubble

**Files:**
- Modify: `lib/ui/message_bubble.dart` — wrap AI bubble with scale animation on completion

When `animatingTextSignal` transitions from non-null to null, apply a
micro-scale pop (0.98 → 1.0, 150ms). Implement via `AnimatedScale` widget
keyed to the message ID, animating when animation completes.

Update `_BubbleContainer` to use `AnimatedScale`:

```dart
// Wrap the container with AnimatedScale
return AnimatedScale(
  scale: animatingTextSignal != null ? 0.98 : 1.0,
  duration: const Duration(milliseconds: 150),
  curve: Curves.easeOut,
  child: container,
);
```

Pass `animatingTextSignal` down to `_BubbleContainer`.

---

### Task 14: Final Run and Smoke Test

**Step 1: Run on web**
```bash
flutter run -d chrome --web-port 3000
```

**Step 2: Run on iOS simulator**
```bash
flutter run -d "iPhone 15"
```

**Step 3: Verify checklist**
- [ ] Chat opens with input enabled
- [ ] Send a message → input disables immediately
- [ ] Typing indicator appears after 650ms if backend is slow
- [ ] AI response animates character by character
- [ ] Input re-enables after animation completes
- [ ] Error bubble appears on network failure with retry
- [ ] After booking: Google Calendar and Apple Calendar buttons appear
- [ ] Google Calendar button opens correct URL
- [ ] Apple Calendar downloads/shares .ics file
- [ ] Web: centered chat column on dark background
- [ ] Mobile: edge-to-edge, safe areas respected
- [ ] Enter sends, Shift+Enter inserts newline
- [ ] No entire-list rebuilds during animation (verify with Flutter DevTools)
