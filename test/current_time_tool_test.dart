import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_ai_agent/models/tool_result.dart';
import 'package:jarvis_ai_agent/tools/current_time_tool.dart';

void main() {
  // Fixed clock: 11 Oct 2026 = रविवार (Sunday), 19:42 = शाम 7:42.
  final DateTime now = DateTime(2026, 10, 11, 19, 42, 7);

  group('TimeFormatting', () {
    test('hindi time', () {
      expect(TimeFormatting.timeText(now, hindi: true), 'शाम 7 बजकर 42 मिनट');
    });

    test('english time uses 12-hour clock', () {
      expect(TimeFormatting.timeText(now, hindi: false), '7:42 PM');
      expect(TimeFormatting.timeText(DateTime(2026, 1, 1, 0, 5), hindi: false),
          '12:05 AM');
    });

    test('hindi date with weekday and month name', () {
      expect(TimeFormatting.dateText(now, hindi: true),
          'रविवार, 11 अक्टूबर 2026');
      expect(TimeFormatting.dateText(DateTime(2026, 3, 3), hindi: false),
          'Tuesday, 3 March 2026');
    });

    test('day parts split the 24 hours correctly', () {
      expect(TimeFormatting.dayPartHindi(3), 'रात');
      expect(TimeFormatting.dayPartHindi(4), 'सुबह');
      expect(TimeFormatting.dayPartHindi(11), 'सुबह');
      expect(TimeFormatting.dayPartHindi(12), 'दोपहर');
      expect(TimeFormatting.dayPartHindi(16), 'शाम');
      expect(TimeFormatting.dayPartHindi(20), 'रात');
      expect(TimeFormatting.hour12(0), 12);
      expect(TimeFormatting.hour12(12), 12);
      expect(TimeFormatting.hour12(13), 1);
    });

    test('timezone offset text, positive and negative', () {
      expect(TimeFormatting.offsetText(const Duration(hours: 5, minutes: 30)),
          '+05:30');
      expect(TimeFormatting.offsetText(const Duration(hours: -8)), '-08:00');
      expect(TimeFormatting.offsetText(Duration.zero), '+00:00');
    });

    test('resultFor honours info= time/date/both', () {
      final ToolResult only =
          TimeFormatting.resultFor(now, info: 'time', hindi: true);
      expect(only.spokenText, 'शाम 7 बजकर 42 मिनट');
      final ToolResult date =
          TimeFormatting.resultFor(now, info: 'date', hindi: true);
      expect(date.spokenText, 'रविवार, 11 अक्टूबर 2026');
      final ToolResult both =
          TimeFormatting.resultFor(now, info: 'both', hindi: true);
      expect(both.spokenText, contains('अक्टूबर'));
      expect(both.spokenText, contains('मिनट'));
    });
  });

  group('CurrentTimeTool', () {
    test('reads the device clock and reports success', () async {
      final ToolResult r = await CurrentTimeTool().run(const ToolRequest(
          name: 'get_current_time', arguments: <String, Object?>{}));
      expect(r.isSuccess, isTrue);
      expect(r.data['iso8601_local'], isNotNull);
      expect(r.data['epoch_ms'], isA<int>());
      expect(r.data['timezone_offset'], isA<String>());
      expect((r.data['epoch_ms'] as int), lessThanOrEqualTo(
          DateTime.now().millisecondsSinceEpoch));
    });

    test('english reply when language=en', () async {
      final ToolResult r = await CurrentTimeTool().run(const ToolRequest(
        name: 'get_current_time',
        arguments: <String, Object?>{'info': 'date', 'language': 'en'},
      ));
      expect(r.spokenText, matches(RegExp(r'\d{4}')));
      expect(r.spokenText, isNot(contains('अक्टूबर')));
    });
  });
}
