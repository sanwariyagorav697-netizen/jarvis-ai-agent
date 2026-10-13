import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_ai_agent/services/local_router.dart';

void main() {
  const LocalRouter router = LocalRouter();

  test('time questions -> get_current_time with info=time', () {
    for (final String phrase in <String>[
      'अभी क्या समय है',
      'समय बताओ',
      'what is the time',
      'घड़ी में कितने बजे हैं',
    ]) {
      final Route r = router.route(phrase);
      expect(r.kind, RouteKind.tool, reason: phrase);
      expect(r.tool!.name, 'get_current_time', reason: phrase);
      expect(r.tool!.arguments['info'], 'time', reason: phrase);
    }
  });

  test('date questions -> info=date (और time से पहले match)', () {
    final Route r = router.route('आज की तारीख़ क्या है');
    expect(r.tool!.arguments['info'], 'date');
  });

  test('task add: title is cleaned of trigger words', () {
    final Route r = router.route('मुझे दवा याद दिलाओ');
    expect(r.kind, RouteKind.tool);
    expect(r.tool!.name, 'add_task');
    expect(r.tool!.arguments['title'], 'दवा');
  });

  test('task add with no real title -> asks back, no tool call', () {
    final Route r = router.route('याद रखो');
    expect(r.kind, RouteKind.reply);
    expect(r.replyText, isNotEmpty);
  });

  test('task list and complete route to their tools', () {
    expect(router.route('मेरे काम दिखाओ').tool!.name, 'list_tasks');
    expect(router.route('दवा वाला काम पूरा कर दिया').tool!.name,
        'complete_task');
  });

  test('speech control wins over tool keywords', () {
    final Route r = router.route('बोलना बंद करो');
    expect(r.kind, RouteKind.reply);
    expect(r.replyText, contains('रोक'));
  });

  test('repeat is its own route kind', () {
    expect(router.route('जवाब दोहराओ').kind, RouteKind.repeat);
  });

  test('unknown request -> none (controller tab honest reply deta hai)', () {
    expect(router.route('kal ka weather kaisa rahega').kind, RouteKind.none);
    expect(router.route('   ').kind, RouteKind.none);
  });

  test('extractTaskTitle keeps the time-of-day, drops the trigger words', () {
    expect(LocalRouter.extractTaskTitle('7 बजे दवा याद दिलाओ'), contains('दवा'));
    expect(LocalRouter.extractTaskTitle('add task: office se milk'),
        contains('office se milk'));
  });
}
