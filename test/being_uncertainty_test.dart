import 'package:arrow_options/arrow_options.dart' show BeingType;
import 'package:flutter_test/flutter_test.dart';

import 'package:explore/astro/being_uncertainty.dart';

void main() {
  group('roddenToUncertainty', () {
    test('null rating returns ExactTime', () {
      expect(roddenToUncertainty(null, 10), isA<ExactTime>());
    });

    test('A rating returns ExactTime', () {
      expect(roddenToUncertainty('A', 10), isA<ExactTime>());
    });

    test('AA rating returns ExactTime', () {
      expect(roddenToUncertainty('AA', 10), isA<ExactTime>());
    });

    test('X rating returns UnknownTime', () {
      expect(roddenToUncertainty('X', 10), isA<UnknownTime>());
    });

    test('C rating at 9am returns morning PeriodTime', () {
      final result = roddenToUncertainty('C', 9);
      expect(result, isA<PeriodTime>());
      final period = result as PeriodTime;
      expect(period.startHour, 6);
      expect(period.endHour, 12);
    });

    test('C rating at 14:00 returns afternoon PeriodTime', () {
      final result = roddenToUncertainty('C', 14);
      expect(result, isA<PeriodTime>());
      final period = result as PeriodTime;
      expect(period.startHour, 12);
      expect(period.endHour, 18);
    });

    test('C rating at 20:00 returns evening PeriodTime', () {
      final result = roddenToUncertainty('C', 20);
      expect(result, isA<PeriodTime>());
      final period = result as PeriodTime;
      expect(period.startHour, 18);
      expect(period.endHour, 0);
    });

    test('C rating at 3am returns night PeriodTime', () {
      final result = roddenToUncertainty('C', 3);
      expect(result, isA<PeriodTime>());
      final period = result as PeriodTime;
      expect(period.startHour, 0);
      expect(period.endHour, 6);
    });

    test('C rating at boundary hour 6 returns morning', () {
      final result = roddenToUncertainty('C', 6) as PeriodTime;
      expect(result.startHour, 6);
      expect(result.endHour, 12);
    });

    test('C rating at boundary hour 12 returns afternoon', () {
      final result = roddenToUncertainty('C', 12) as PeriodTime;
      expect(result.startHour, 12);
      expect(result.endHour, 18);
    });

    test('C rating at boundary hour 18 returns evening', () {
      final result = roddenToUncertainty('C', 18) as PeriodTime;
      expect(result.startHour, 18);
      expect(result.endHour, 0);
    });

    test('C rating at boundary hour 0 returns night', () {
      final result = roddenToUncertainty('C', 0) as PeriodTime;
      expect(result.startHour, 0);
      expect(result.endHour, 6);
    });
  });

  group('BeingUncertainty', () {
    final beingA = Being(name: 'Indra', type: BeingType.aditya, signNumber: 1);
    final beingB = Being(name: 'Surya', type: BeingType.aditya, signNumber: 5);
    final beingC = Being(name: 'Vritra', type: BeingType.naga, signNumber: 3);

    test('none has no uncertainty for any planet', () {
      expect(BeingUncertainty.none.isUncertain('venus'), false);
      expect(BeingUncertainty.none.isTrimsamsaUncertain('mars'), false);
      expect(BeingUncertainty.none.isHoraUncertain('jupiter'), false);
    });

    test('none returns empty lists for accessors', () {
      expect(BeingUncertainty.none.trimsamsaFor('venus'), isEmpty);
      expect(BeingUncertainty.none.horaFor('venus'), isEmpty);
    });

    test('isTrimsamsaUncertain true when multiple options', () {
      final u = BeingUncertainty(
        trimsamsaOptions: {
          'venus': [beingA, beingB],
        },
      );
      expect(u.isTrimsamsaUncertain('venus'), true);
      expect(u.isTrimsamsaUncertain('mars'), false);
    });

    test('isTrimsamsaUncertain false when single option', () {
      final u = BeingUncertainty(
        trimsamsaOptions: {
          'venus': [beingA],
        },
      );
      expect(u.isTrimsamsaUncertain('venus'), false);
    });

    test('isHoraUncertain true when multiple options', () {
      final u = BeingUncertainty(
        horaOptions: {
          'mars': [beingA, beingC],
        },
      );
      expect(u.isHoraUncertain('mars'), true);
      expect(u.isHoraUncertain('venus'), false);
    });

    test('isUncertain true if either trimsamsa or hora uncertain', () {
      final trimsamsaOnly = BeingUncertainty(
        trimsamsaOptions: {
          'venus': [beingA, beingB],
        },
      );
      expect(trimsamsaOnly.isUncertain('venus'), true);

      final horaOnly = BeingUncertainty(
        horaOptions: {
          'venus': [beingA, beingC],
        },
      );
      expect(horaOnly.isUncertain('venus'), true);
    });

    test('trimsamsaFor returns options list', () {
      final u = BeingUncertainty(
        trimsamsaOptions: {
          'venus': [beingA, beingB],
        },
      );
      expect(u.trimsamsaFor('venus'), [beingA, beingB]);
      expect(u.trimsamsaFor('mars'), isEmpty);
    });

    test('horaFor returns options list', () {
      final u = BeingUncertainty(
        horaOptions: {
          'jupiter': [beingA, beingC],
        },
      );
      expect(u.horaFor('jupiter'), [beingA, beingC]);
      expect(u.horaFor('saturn'), isEmpty);
    });

    test('Being fields accessible for UI rendering', () {
      expect(beingA.name, 'Indra');
      expect(beingA.type.name, 'aditya');
      expect(beingA.signNumber, 1);
    });
  });
}
