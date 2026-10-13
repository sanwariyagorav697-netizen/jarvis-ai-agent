import '../models/tool_result.dart';

/// Local (offline) command router.
///
/// Ye AI ka replacement NAHI hai — ye wo chhota set hai jo device par hi,
/// bina network ke, sach me kaam karta hai. Phase 4 me online model isi
/// [ToolRegistry] ko tool-calling ke liye use karega; agar network/model fail
/// ho jaye to router fallback banta hai.
enum RouteKind { tool, reply, repeat, none }

class Route {
  const Route._({required this.kind, this.tool, this.replyText});

  factory Route.tool(ToolRequest request) =>
      Route._(kind: RouteKind.tool, tool: request);

  factory Route.reply(String text) =>
      Route._(kind: RouteKind.reply, replyText: text);

  const Route.repeatLast() : this._(kind: RouteKind.repeat);

  static const Route none = Route._(kind: RouteKind.none);

  final RouteKind kind;
  final ToolRequest? tool;
  final String? replyText;
}

class LocalRouter {
  const LocalRouter();

  static final RegExp _taskNoise = RegExp(
    r'(मुझे|मुझको|प्लीज़|कृपया|याद\s*(रखो|रखना|रखा|दिलाओ|दिलाना|दिलवाओ)'
    r'|रिमाइंडर|रिमाइन्डर|रिमाइंड|reminder|remind|task|काम|कामों|जोड़ो|जोड़\s*दो|जोड़\s*दिया'
    r'|add|new|नया|नई|याद)\s*[:\-]?',
    caseSensitive: false,
  );

  static final RegExp _leadingJunk =
      RegExp(r'^[\s:,.\-किकीकाके\s]+', caseSensitive: false);

  /// "मुझे 7 बजे दवा याद दिलाओ" -> "7 बजे दवा"
  static String extractTaskTitle(String input) {
    String t = input.trim();
    t = t.replaceAll(_taskNoise, ' ');
    t = t.replaceAll(_leadingJunk, '');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  Route route(String input) {
    final String s = input.toLowerCase().trim();
    if (s.isEmpty) return Route.none;
    bool hasAny(List<String> words) => words.any(s.contains);

    // 1) Speech control pehle — warna "time बंद करो" tool ban jata.
    if (hasAny(<String>[
      'बंद करो', 'रोको', 'रुक जाओ', 'चुप', 'बोलना बंद',
      'stop speaking', 'shut up', 'stop it',
    ])) {
      return Route.reply('ठीक है, बोलना रोक दिया।');
    }
    if (hasAny(<String>[
      'दोहराओ', 'फिर से बोलो', 'फिर से सुनाओ', 'repeat', 'फिर बोलो',
    ])) {
      return const Route.repeatLast();
    }

    // 2) Task list tools
    if (hasAny(<String>[
      'काम दिखाओ', 'काम दिखा', 'मेरे काम', 'काम की लिस्ट', 'task list',
      'list task', 'mere kaam', 'क्या काम बाकी',
    ])) {
      return Route.tool(const ToolRequest(
          name: 'list_tasks', arguments: <String, Object?>{}));
    }
    if (hasAny(<String>[
      'पूरा कर दिया', 'पूरा हो गया', 'काम खत्म', 'कर दिया', 'done कर',
      'complete task', 'mark done',
    ])) {
      return Route.tool(ToolRequest(
          name: 'complete_task',
          arguments: <String, Object?>{'match': extractTaskTitle(input)}));
    }
    if (hasAny(<String>[
      'याद रखो', 'याद रखना', 'याद दिला', 'रिमाइंडर', 'रिमाइंड', 'reminder',
      'add task', 'काम जोड़', 'task जोड़', 'लिस्ट में जोड़',
    ])) {
      final String title = extractTaskTitle(input);
      if (title.isEmpty) {
        return Route.reply('क्या जोड़ना है, वो भी तो बताइए।');
      }
      return Route.tool(ToolRequest(
          name: 'add_task', arguments: <String, Object?>{'title': title}));
    }

    // 3) Time / date
    if (hasAny(<String>[
      'तारीख', 'तारिक', 'डेट क्या', 'की डेट', 'कौन सा दिन', 'कौनसा दिन',
      'आज कौन', 'date kya', 'what date', 'किस साल', ' कौन से साल',
    ])) {
      return Route.tool(const ToolRequest(
          name: 'get_current_time',
          arguments: <String, Object?>{'info': 'date', 'language': 'hi'}));
    }
    if (hasAny(<String>[
      'समय', 'बज', 'टाइम', 'time', 'clock', 'baje', 'बजे',
    ])) {
      return Route.tool(const ToolRequest(
          name: 'get_current_time',
          arguments: <String, Object?>{'info': 'time', 'language': 'hi'}));
    }

    // 4) Honest self-description (koi fake capability claim nahi)
    if (hasAny(<String>[
      'तुम कौन', 'कौन हो', 'who are you', 'kya kar sakte', 'क्या कर सकते',
      'मदद', 'help', 'क्या कर सकते हो',
    ])) {
      return Route.reply(
        'मैं JARVIS हूँ — आपका फ़ोन असिस्टेंट। अभी मैं ये कर सकता हूँ: समय और '
        'तारीख़ बता सकता हूँ, इन-ऐप कामों की लिस्ट बना सकता हूँ, और आपकी आवाज़ '
        'समझकर बोलकर जवाब देता हूँ। ऑनलाइन AI और फ़ोन के ऐप्स खोलना आगे के '
        'फेज़ में जुड़ेगा।',
      );
    }
    if (hasAny(<String>[
      'मेरा डेटा', 'डाटा कहाँ', 'data कहाँ', 'privacy', 'गोपनीय', 'कौन देख सकता',
    ])) {
      return Route.reply(
        'अभी सब कुछ इसी फ़ोन पर रहता है — टाइम और कामों की लिस्ट डिवाइस पर बनती '
        'है, इंटरनेट पर कुछ जाता ही नहीं। जब ऑनलाइन AI जुड़ेगा, तब आपका सवाल '
        'उसी provider के सर्वर पर जाएगा, और ऐप में यही लिखा दिखेगा।',
      );
    }

    return Route.none;
  }
}
