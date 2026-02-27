import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chat_message.dart';
import '../services/ics_downloader.dart';
import '../theme/app_theme.dart';

/// Two side-by-side calendar integration buttons rendered below a confirmed
/// appointment bubble. Only shown when [event] is non-null.
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
    DateTime start;
    DateTime end;

    try {
      start = DateTime.parse(event.startIso);
      end = DateTime.parse(event.endIso);
    } catch (e) {
      debugPrint('CalendarButtons: failed to parse event dates: $e');
      return;
    }

    final uri = Uri.https('calendar.google.com', '/calendar/render', {
      'action': 'TEMPLATE',
      'text': event.title,
      'dates': '${_toGoogleDateFormat(start)}/${_toGoogleDateFormat(end)}',
      'details': event.description,
      'location': event.location ?? 'Vitable Health',
    });

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch Google Calendar URL');
    }
  }

  /// Formats a DateTime to Google Calendar format: YYYYMMDDTHHMMSSZ
  String _toGoogleDateFormat(DateTime dt) {
    final u = dt.toUtc();
    return '${u.year.toString().padLeft(4, '0')}'
        '${u.month.toString().padLeft(2, '0')}'
        '${u.day.toString().padLeft(2, '0')}'
        'T${u.hour.toString().padLeft(2, '0')}'
        '${u.minute.toString().padLeft(2, '0')}'
        '${u.second.toString().padLeft(2, '0')}Z';
  }

  // ── Apple Calendar / ICS ──────────────────────────────────────────────────

  Future<void> _downloadIcs() async {
    DateTime start;
    DateTime end;

    try {
      start = DateTime.parse(event.startIso);
      end = DateTime.parse(event.endIso);
    } catch (e) {
      debugPrint('CalendarButtons: failed to parse event dates: $e');
      return;
    }

    final ics = _buildIcs(start, end);
    const filename = 'vitable_appointment.ics';

    await downloadIcs(ics, filename);
  }

  String _buildIcs(DateTime start, DateTime end) {
    final stamp = _toIcsFormat(DateTime.now().toUtc());
    final dtStart = _toIcsFormat(start.toUtc());
    final dtEnd = _toIcsFormat(end.toUtc());
    final uid = '${DateTime.now().millisecondsSinceEpoch}@vitablehealth.com';

    return 'BEGIN:VCALENDAR\r\n'
        'VERSION:2.0\r\n'
        'PRODID:-//Vitable Health//Chat//EN\r\n'
        'BEGIN:VEVENT\r\n'
        'UID:$uid\r\n'
        'DTSTAMP:$stamp\r\n'
        'DTSTART:$dtStart\r\n'
        'DTEND:$dtEnd\r\n'
        'SUMMARY:${event.title}\r\n'
        'DESCRIPTION:${event.description.replaceAll('\n', '\\n')}\r\n'
        'LOCATION:${event.location ?? 'Vitable Health'}\r\n'
        'END:VEVENT\r\n'
        'END:VCALENDAR\r\n';
  }

  /// Formats a UTC DateTime to ICS format: YYYYMMDDTHHMMSSZ
  String _toIcsFormat(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}'
        '${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}'
        'T${dt.hour.toString().padLeft(2, '0')}'
        '${dt.minute.toString().padLeft(2, '0')}'
        '${dt.second.toString().padLeft(2, '0')}Z';
  }
}

// ── Button Widget ─────────────────────────────────────────────────────────────

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
