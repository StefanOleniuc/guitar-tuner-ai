import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tuner_ai/utils/one_euro_filter.dart';

void main() {
  group('OneEuroFilter — comportament', () {
    test('prima valoare se întoarce neschimbată', () {
      final f = OneEuroFilter();
      expect(f.filter(100.0, 0), equals(100.0));
    });

    test('valoare constantă → convergență netedă fără overshoot', () {
      final f = OneEuroFilter();
      f.filter(100.0, 0);
      double last = 100.0;
      for (int t = 16; t <= 500; t += 16) {
        final v = f.filter(100.0, t);
        expect(v, closeTo(100.0, 0.5));
        last = v;
      }
      expect(last, closeTo(100.0, 0.001));
    });

    test('treaptă mare → urmărire rapidă (beta-driven)', () {
      final f = OneEuroFilter();
      f.filter(82.0, 0);
      // Treaptă bruscă de la 82 (E2) la 110 (A2)
      double v = 0;
      for (int t = 16; t <= 200; t += 16) {
        v = f.filter(110.0, t);
      }
      // După 200ms valoarea filtrată trebuie să fie aproape de 110.
      expect(v, greaterThan(105));
    });

    test('reset() șterge starea internă', () {
      final f = OneEuroFilter();
      f.filter(100.0, 0);
      f.filter(150.0, 50);
      f.reset();
      // După reset, prima valoare se întoarce neschimbată din nou.
      expect(f.filter(200.0, 0), equals(200.0));
    });

    test('dt non-pozitiv tratat ca 16ms (nu împarte la 0)', () {
      final f = OneEuroFilter();
      f.filter(100.0, 100);
      // dt = 0 → nu trebuie să arunce / NaN
      final v = f.filter(105.0, 100);
      expect(v.isFinite, isTrue);
    });
  });
}
