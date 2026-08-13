import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

/// The cases the React client's summary panel pinned before it was retired.
void main() {
  test('merges repeated craft lines into one total', () {
    expect(
      consolidateAwayMessages(<String>[
        'Won 2 fights while away.',
        'Crafted 1 Baked Potato (+120 XP)',
        'Crafted 1 Baked Potato (+120 XP)',
        'Defeated by Cow while away.',
      ]),
      <String>[
        'Won 2 fights while away.',
        'Crafted 2 Baked Potato (+240 XP)',
        'Defeated by Cow while away.',
      ],
    );
  });

  test('keeps different crafted items on separate lines, in the order they arrived', () {
    expect(
      consolidateAwayMessages(<String>[
        'Crafted 1 Baked Potato (+120 XP)',
        'Crafted 2 Copper Bar (+50 XP)',
        'Crafted 1 Baked Potato (+120 XP)',
      ]),
      <String>['Crafted 2 Baked Potato (+240 XP)', 'Crafted 2 Copper Bar (+50 XP)'],
    );
  });

  test('leaves everything that is not a craft line alone', () {
    final messages = <String>[
      'Gathered through 312 actions while away.',
      '…and 16 more crafts.',
      'Activity stopped — requirements no longer met.',
    ];
    expect(consolidateAwayMessages(messages), messages);
    expect(consolidateAwayMessages(const <String>[]), isEmpty);
  });
}
