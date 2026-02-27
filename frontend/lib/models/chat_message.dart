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
/// start_iso and end_iso are ISO 8601 UTC strings (e.g. "2026-03-05T14:00:00+00:00").
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
