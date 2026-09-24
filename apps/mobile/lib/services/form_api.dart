import 'package:dio/dio.dart';
import 'package:form_mobile/models/server_info.dart';

// Stable categories keep server messages and personal payloads out of UI/logs.
enum ApiFailure { unavailable, missingSession, incompatible, rejected }

class FormApiException implements Exception {
  const FormApiException(this.failure);

  final ApiFailure failure;
}

class FormApi {
  FormApi(this._dio);

  factory FormApi.connect(Uri baseUrl) => FormApi(
    Dio(
      BaseOptions(
        baseUrl: baseUrl.toString(),
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        headers: {'Accept': 'application/json'},
      ),
    ),
  );

  final Dio _dio;

  Future<Map<String, dynamic>> _get(String path) async {
    try {
      final response = await _dio.get<Object?>(path);
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const FormApiException(ApiFailure.incompatible);
      }
      return data;
    } on DioException catch (error) {
      throw FormApiException(mapFailure(error));
    }
  }

  static ApiFailure mapFailure(DioException error) {
    if (error.error is FormatException) return ApiFailure.incompatible;
    final data = error.response?.data;
    final code =
        data is Map<String, dynamic> && data['error'] is Map<String, dynamic>
        ? (data['error'] as Map<String, dynamic>)['code']
        : null;
    if (code == 'authentication-required') return ApiFailure.missingSession;
    if (error.response?.statusCode == 401) return ApiFailure.missingSession;
    if (error.response?.statusCode == 404) return ApiFailure.incompatible;
    if (error.type != DioExceptionType.badResponse ||
        (error.response?.statusCode ?? 0) >= 500) {
      return ApiFailure.unavailable;
    }
    return ApiFailure.rejected;
  }

  Future<ServerInfo> serverInfo() async {
    final data = await _get('v1/meta');
    try {
      return ServerInfo.fromJson(data);
    } on Object {
      throw const FormApiException(ApiFailure.incompatible);
    }
  }

  Future<PersonalSession> session() async {
    final data = await _get('v1/auth/session');
    try {
      final session = PersonalSession.fromJson(
        data['session'] as Map<String, dynamic>,
      );
      if (session.accountId.isEmpty) {
        throw const FormatException('Missing account identifier');
      }
      return session;
    } on Object {
      throw const FormApiException(ApiFailure.incompatible);
    }
  }

  Future<int> collectionCount({required bool feed}) async {
    final data = await _get(feed ? 'v1/looks' : 'v1/wardrobe-items');
    final records = data[feed ? 'looks' : 'wardrobeItems'];
    if (records is! List<dynamic>) {
      throw const FormApiException(ApiFailure.incompatible);
    }
    return records.length;
  }

  void close() => _dio.close();
}
