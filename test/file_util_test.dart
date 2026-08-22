import 'package:flutter_test/flutter_test.dart';

import 'package:explore/file_util.dart';

void main() {
  group('chartFileStem', () {
    test('passes through a plain name', () {
      expect(chartFileStem('Josh'), 'Josh');
    });

    test('sanitizes disallowed characters to underscores', () {
      expect(chartFileStem('Jane Doe / 2'), 'Jane_Doe___2');
    });

    test('keeps interior dots (so appended extension stays valid)', () {
      expect(chartFileStem('15.05.1990'), '15.05.1990');
    });

    // Regression: an empty name produced '.toml', which package:path treats as
    // an extensionless dotfile — file_picker's web save guard then threw
    // "The file name should include a valid file extension" and nothing saved.
    test('empty name falls back to chart', () {
      expect(chartFileStem(''), 'chart');
    });

    test('null name falls back to chart', () {
      expect(chartFileStem(null), 'chart');
    });

    test('strips leading dots so the stem never begins with one', () {
      expect(chartFileStem('.hidden'), 'hidden');
      expect(chartFileStem('...'), 'chart');
    });
  });
}
