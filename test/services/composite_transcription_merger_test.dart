import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_vibrance/services/composite_transcription_merger.dart';

const _slots = [
  CompositeHypothesis(label: 'OpenAI', text: 'Работаю я от офиса, ок?'),
  CompositeHypothesis(label: 'Google', text: 'работаю я топус ок'),
];

void main() {
  test('word diff keeps agreements and brackets disagreements', () {
    expect(
      wordDiff(_slots[0].text, _slots[1].text, labelA: 'S1', labelB: 'S2'),
      'Работаю я [S1: от офиса, | S2: топус] ок?',
    );
    expect(wordDiff('a b', 'a b c'), 'a b [A: ∅ | B: c]');
  });

  test('sends all slots and the diff to DeepSeek with reasoning off', () async {
    late Map<String, dynamic> body;
    final merger = CompositeTranscriptionMerger(
      apiKey: 'or-key',
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'Работаю я от Opus, ок?'},
                },
              ],
            }),
          ),
          200,
        );
      }),
    );

    expect(await merger.merge(_slots), 'Работаю я от Opus, ок?');
    expect(body['model'], 'deepseek/deepseek-v4.1-flash');
    expect(body['reasoning'], {'enabled': false, 'exclude': true});
    expect(body['provider'], {'sort': 'latency'});
    expect(body['temperature'], 0);
    final user = body['messages'][1]['content'] as String;
    expect(user, contains('Slot 2 (Google):\nработаю я топус ок'));
    expect(user, contains('[Slot 1: от офиса, | Slot 2: топус]'));
  });

  test('fails open to the first non-empty slot', () async {
    const withEmptyFirst = [
      CompositeHypothesis(label: 'OpenAI', text: '  '),
      ..._slots,
    ];
    final noKey = CompositeTranscriptionMerger(apiKey: null);
    expect(await noKey.merge(withEmptyFirst), _slots.first.text);

    final broken = CompositeTranscriptionMerger(
      apiKey: 'or-key',
      client: MockClient((_) async => http.Response('boom', 500)),
    );
    expect(await broken.merge(withEmptyFirst), _slots.first.text);

    final rambling = CompositeTranscriptionMerger(
      apiKey: 'or-key',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'Sure! ' * 40},
              },
            ],
          }),
          200,
        ),
      ),
    );
    expect(await rambling.merge(_slots), _slots.first.text);
    expect(await noKey.merge(const []), '');
  });
}
