import 'dart:convert';
import 'dart:typed_data';

import '../../domain/models/reminder.dart';
import 'export_service.dart';

class CalendarEvent {
  const CalendarEvent({
    required this.uid,
    required this.title,
    required this.date,
    this.description,
  });

  final String uid;
  final String title;
  final DateTime date;
  final String? description;
}

/// Builds and saves `.ics` calendar files for due reminders.
class CalendarExportService {
  const CalendarExportService._();

  static Future<String> exportReminder(
    ReminderItem reminder, {
    String? description,
  }) {
    final event = CalendarEvent(
      uid: '${reminder.kind.name}-${reminder.id}@receipt-tracker',
      title: reminder.title,
      date: reminder.dueDate,
      description: description,
    );
    return exportEvents(<CalendarEvent>[event], filename: 'reminder.ics');
  }

  static Future<String> exportEvents(
    List<CalendarEvent> events, {
    required String filename,
  }) async {
    final bytes = Uint8List.fromList(
      utf8.encode(buildIcs(events)),
    );
    return ExportService.saveBytes(
      bytes,
      filename,
      'text/calendar; charset=utf-8',
    );
  }

  static String buildIcs(List<CalendarEvent> events, {DateTime? now}) {
    final stamp = _utcStamp(now ?? DateTime.now());
    final buffer = StringBuffer()
      ..write('BEGIN:VCALENDAR\r\n')
      ..write('VERSION:2.0\r\n')
      ..write('PRODID:-//Receipt Tracker//Due reminders//EN\r\n')
      ..write('CALSCALE:GREGORIAN\r\n')
      ..write('METHOD:PUBLISH\r\n');
    for (final event in events) {
      final start = _dateStamp(event.date);
      final end = _dateStamp(
        DateTime(event.date.year, event.date.month, event.date.day + 1),
      );
      buffer
        ..write('BEGIN:VEVENT\r\n')
        ..write('UID:${_escape(event.uid)}\r\n')
        ..write('DTSTAMP:$stamp\r\n')
        ..write('DTSTART;VALUE=DATE:$start\r\n')
        ..write('DTEND;VALUE=DATE:$end\r\n')
        ..write('SUMMARY:${_escape(event.title)}\r\n');
      if (event.description != null && event.description!.trim().isNotEmpty) {
        buffer.write('DESCRIPTION:${_escape(event.description!)}\r\n');
      }
      buffer.write('END:VEVENT\r\n');
    }
    buffer.write('END:VCALENDAR\r\n');
    return buffer.toString();
  }

  static String _dateStamp(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';

  static String _utcStamp(DateTime date) {
    final utc = date.toUtc();
    return '${_dateStamp(utc)}T${utc.hour.toString().padLeft(2, '0')}'
        '${utc.minute.toString().padLeft(2, '0')}'
        '${utc.second.toString().padLeft(2, '0')}Z';
  }

  static String _escape(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\r\n', r'\n')
      .replaceAll('\n', r'\n');
}
