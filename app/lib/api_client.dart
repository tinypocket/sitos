import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

import 'models.dart';

/// Thrown when a barcode/food isn't found anywhere (cache or providers).
class NotFoundException implements Exception {}

/// Talks to the Sitos API.
///
/// The default base URL targets an Android emulator, which reaches the host
/// machine at 10.0.2.2. Override via --dart-define=SITOS_API_BASE=... for a
/// physical device (use your machine's LAN IP) or a deployed environment.
class SitosApi {
  SitosApi({String? baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl ??
              const String.fromEnvironment('SITOS_API_BASE',
                  defaultValue: 'http://10.0.2.2:5000'),
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ));

  final Dio _dio;
  static final _dateFmt = DateFormat('yyyy-MM-dd');

  Future<Food> getFoodByBarcode(String code) async {
    try {
      final res = await _dio.get('/api/foods/barcode/$code');
      return Food.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) throw NotFoundException();
      rethrow;
    }
  }

  Future<List<Food>> searchFoods(String query) async {
    final res = await _dio.get('/api/foods/search',
        queryParameters: {'q': query});
    return (res.data as List)
        .map((e) => Food.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Food> createUserFood(Map<String, dynamic> body) async {
    final res = await _dio.post('/api/foods', data: body);
    return Food.fromJson(res.data as Map<String, dynamic>);
  }

  Future<DiaryDay> getDiary(DateTime date) async {
    final res = await _dio.get('/api/diary',
        queryParameters: {'date': _dateFmt.format(date)});
    return DiaryDay.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> addDiaryEntry({
    required String foodId,
    required DateTime date,
    required double quantity,
    required QuantityUnit unit,
  }) async {
    await _dio.post('/api/diary', data: {
      'foodId': foodId,
      'date': _dateFmt.format(date),
      'quantity': quantity,
      'unit': unit.index,
    });
  }

  Future<void> updateDiaryEntry({
    required String id,
    required String foodId,
    required DateTime date,
    required double quantity,
    required QuantityUnit unit,
  }) async {
    await _dio.put('/api/diary/$id', data: {
      'foodId': foodId,
      'date': _dateFmt.format(date),
      'quantity': quantity,
      'unit': unit.index,
    });
  }

  Future<void> deleteDiaryEntry(String id) async {
    await _dio.delete('/api/diary/$id');
  }

  Future<List<Food>> getRecentFoods() async {
    final res = await _dio.get('/api/diary/recent-foods');
    return (res.data as List)
        .map((e) => Food.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Goal?> getGoal() async {
    final res = await _dio.get('/api/profile/goal');
    if (res.statusCode == 204 || res.data == null) return null;
    return Goal.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Goal> setGoal(int dailyCalorieTarget) async {
    final res = await _dio.put('/api/profile/goal',
        data: {'dailyCalorieTarget': dailyCalorieTarget});
    return Goal.fromJson(res.data as Map<String, dynamic>);
  }
}
