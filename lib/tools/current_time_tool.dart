import '../models/tool_result.dart';
import '../services/tool_registry.dart';

/// Device ki ghadi + calendar se real time/date. Network nahi chahiye, aur
/// jawab device par hi banta hai (isliye "डिवाइस पर" source label lagta hai).
class CurrentTimeTool extends JarvisTool {
  CurrentTimeTool()
      : super(
          name: 'get_current_time',
          description:
              'Device ki current date, time, weekday aur timezone batata hai.',
          params: const <String, ToolParam>{
            'info': ToolParam(
              type: 'string',
              description: 'Kya chahiye: time, date, ya both.',
              required: false,
              enumValues: <String>['time', 'date', 'both'],
            ),
            'language': ToolParam(
              type: 'string',
              description: 'Jawab ki bhasha: hi ya en.',
              required: false,
              enumValues: <String>['hi', 'en'],
            ),
          },
        );

  @override
  Future<ToolResult> run(ToolRequest request) async {
    final String info = (request['info'] as String?) ?? 'both';
    final bool hindi = ((request['language'] as String?) ?? 'hi') != 'en';
    return TimeFormatting.resultFor(DateTime.now(), info: info, hindi: hindi);
  }
}

/// Date/time formatting — pure function, device ke bina bhi test ho sakti hai.
abstract final class TimeFormatting {

  static const List<String> hindiMonths = <String>[
    'जनवरी', 'फ़रवरी', 'मार्च', 'अप्रैल', 'मई', 'जून',
    'जुलाई', 'अगस्त', 'सितम्बर', 'अक्टूबर', 'नवम्बर', 'दिसम्बर',
  ];
  static const List<String> englishMonths = <String>[
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const List<String> hindiDays = <String>[
    'सोमवार', 'मंगलवार', 'बुधवार', 'गुरुवार', 'शुक्रवार', 'शनिवार', 'रविवार',
  ];
  static const List<String> englishDays = <String>[
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  static String dayPartHindi(int hour24) {
    if (hour24 >= 4 && hour24 < 12) return 'सुबह';
    if (hour24 >= 12 && hour24 < 16) return 'दोपहर';
    if (hour24 >= 16 && hour24 < 20) return 'शाम';
    return 'रात';
  }

  static int hour12(int hour24) {
    final int h = hour24 % 12;
    return h == 0 ? 12 : h;
  }

  static String timeText(DateTime now, {required bool hindi}) {
    final int h12 = hour12(now.hour);
    final String minutes = now.minute.toString().padLeft(2, '0');
    return hindi
        ? '${dayPartHindi(now.hour)} $h12 बजकर ${minutes} मिनट'
        : '$h12:$minutes ${now.hour < 12 ? 'AM' : 'PM'}';
  }

  static String dateText(DateTime now, {required bool hindi}) => hindi
      ? '${hindiDays[now.weekday - 1]}, ${now.day} ${hindiMonths[now.month - 1]} ${now.year}'
      : '${englishDays[now.weekday - 1]}, ${now.day} ${englishMonths[now.month - 1]} ${now.year}';

  /// Ek 24-घंटे का offset, e.g. "+05:30". DateTime.timeZoneOffset se.
  static String offsetText(Duration offset) {
    final String sign = offset.isNegative ? '-' : '+';
    final Duration abs = offset.abs();
    return '$sign${abs.inHours.toString().padLeft(2, '0')}:'
        '${(abs.inMinutes % 60).toString().padLeft(2, '0')}';
  }

  static ToolResult resultFor(DateTime now,
      {required String info, required bool hindi}) {
    final List<String> parts = <String>[];
    if (info != 'date') parts.add(timeText(now, hindi: hindi));
    if (info != 'time') parts.add(dateText(now, hindi: hindi));
    final String spoken = parts.join(hindi ? ' — ' : ', ');
    return ToolResult.ok(
      'get_current_time',
      spokenText: spoken,
      data: <String, Object?>{
        'iso8601_local': now.toIso8601String(),
        'epoch_ms': now.millisecondsSinceEpoch,
        'utc_iso8601': now.toUtc().toIso8601String(),
        'time': '${now.hour.toString().padLeft(2, '0')}:'
            '${now.minute.toString().padLeft(2, '0')}',
        'date': '${now.year}-'
            '${now.month.toString().padLeft(2, '0')}-'
            '${now.day.toString().padLeft(2, '0')}',
        'weekday': englishDays[now.weekday - 1],
        'timezone_offset': offsetText(now.timeZoneOffset),
      },
    );
  }
}
