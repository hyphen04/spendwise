import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/utils/money_format.dart';

/// Guards the full-amount formatter used on the home + transactions screens:
/// no K/L/Cr abbreviation, Indian grouping, trailing decimals dropped for
/// whole numbers.
void main() {
  group('fmtGrouped', () {
    test('whole numbers drop the decimal tail', () {
      expect(fmtGrouped(950), '950');
      expect(fmtGrouped(12500), '12,500');
      expect(fmtGrouped(150000), '1,50,000');
      expect(fmtGrouped(12000000), '1,20,00,000');
    });

    test('fractional amounts keep up to two places', () {
      expect(fmtGrouped(12500.5), '12,500.5');
      expect(fmtGrouped(12500.56), '12,500.56');
      expect(fmtGrouped(150000.5), '1,50,000.5');
    });

    test('uses the magnitude (sign is the caller\'s job)', () {
      expect(fmtGrouped(-12500), '12,500');
    });

    test('zero', () {
      expect(fmtGrouped(0), '0');
    });
  });

  group('fmtMoney (compact, unchanged)', () {
    test('still abbreviates for report/forecast contexts', () {
      expect(fmtMoney(12500), '₹12.5K');
      expect(fmtMoney(150000), '₹1.5L');
      expect(fmtMoney(12000000), '₹1.2Cr');
    });
  });
}