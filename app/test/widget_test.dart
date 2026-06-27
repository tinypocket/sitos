import 'package:flutter_test/flutter_test.dart';

import 'package:sitos/models.dart';

void main() {
  test('DiaryEntry parses and exposes scaled nutrition from the API', () {
    final entry = DiaryEntry.fromJson({
      'id': '11111111-1111-1111-1111-111111111111',
      'date': '2026-06-26',
      'quantity': 30,
      'unit': 1,
      'calories': 161.7,
      'protein': 1.9,
      'carbs': 17.2,
      'fat': 9.3,
      'food': {
        'id': '22222222-2222-2222-2222-222222222222',
        'barcode': '3017620422003',
        'name': 'Nutella',
        'brand': 'Ferrero',
        'servingSizeGrams': null,
        'servingSizeLabel': null,
        'caloriesPer100g': 539,
        'proteinPer100g': 6.3,
        'carbsPer100g': 57.5,
        'fatPer100g': 30.9,
        'source': 0,
        'verifiedStatus': 0,
      },
    });

    expect(entry.unit, QuantityUnit.grams);
    expect(entry.calories, 161.7);
    expect(entry.food.name, 'Nutella');
  });
}
