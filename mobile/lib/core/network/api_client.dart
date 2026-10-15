import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/token_storage.dart';

/// Riverpod provider for [ApiClient].
final apiClientProvider = Provider<ApiClient>((ref) {
  final tokenStorage = ref.watch(tokenStorageProvider);
  return ApiClient(tokenStorage: tokenStorage);
});

/// Generic wrapper for successful API responses with standard { data, meta } structure.
class ApiResponse<T> {
  final T data;
  final Map<String, dynamic>? meta;

  const ApiResponse({
    required this.data,
    this.meta,
  });

  @override
  String toString() => 'ApiResponse(data: $data, meta: $meta)';
}

/// Typed exception representing API failures returned from the server or network layer.
class ApiException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;
  final dynamic details;

  const ApiException({
    required this.message,
    this.code,
    this.statusCode,
    this.details,
  });

  @override
  String toString() {
    return 'ApiException(statusCode: $statusCode, code: $code, message: $message)';
  }
}

/// Single Dio wrapper handling base URL configuration, bearer token injection,
/// response envelope unwrapping, and 401 token clearing.
class ApiClient {
  final Dio dio;
  final TokenStorage tokenStorage;
  final void Function()? onUnauthorized;

  ApiClient({
    required this.tokenStorage,
    this.onUnauthorized,
    String? baseUrl,
    Dio? customDio,
  }) : dio = customDio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl ??
                    const String.fromEnvironment(
                      'API_BASE_URL',
                      defaultValue: 'http://localhost:8085/api/v1',
                    ),
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 15),
                headers: const {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
              ),
            ) {
    _setupInterceptors();
  }

  void _setupInterceptors() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await tokenStorage.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException err, handler) async {
          if (err.response?.statusCode == 401) {
            await tokenStorage.deleteToken();
            onUnauthorized?.call();
          }
          return handler.next(err);
        },
      ),
    );
  }

  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await dio.get<dynamic>(
        path,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
      return _unwrapResponse<T>(response);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<ApiResponse<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      Options? effectiveOptions = options;
      if (data is FormData) {
        effectiveOptions = (effectiveOptions ?? Options()).copyWith(
          contentType: 'multipart/form-data',
        );
      }
      final response = await dio.post<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: effectiveOptions,
        cancelToken: cancelToken,
      );
      return _unwrapResponse<T>(response);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<ApiResponse<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await dio.put<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
      return _unwrapResponse<T>(response);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<ApiResponse<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await dio.patch<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
      return _unwrapResponse<T>(response);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<ApiResponse<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await dio.delete<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
      return _unwrapResponse<T>(response);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  ApiResponse<T> _unwrapResponse<T>(Response<dynamic> response) {
    final body = response.data;

    // Check for HTTP 401 specifically
    if (response.statusCode == 401) {
      tokenStorage.deleteToken();
      onUnauthorized?.call();
    }

    if (body is Map<String, dynamic>) {
      // Check if error payload is present
      if (body.containsKey('error') && body['error'] != null) {
        final err = body['error'];
        if (err is Map<String, dynamic>) {
          throw ApiException(
            message: err['message']?.toString() ?? 'Unknown API error',
            code: err['code']?.toString(),
            statusCode: response.statusCode,
            details: err,
          );
        } else {
          throw ApiException(
            message: err.toString(),
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse<T>(
        data: body['data'] as T,
        meta: body['meta'] is Map<String, dynamic>
            ? body['meta'] as Map<String, dynamic>
            : null,
      );
    }

    if (body is T) {
      return ApiResponse<T>(data: body);
    }

    if (response.statusCode == 204 || body == null) {
      return ApiResponse<T>(data: null as T);
    }

    throw ApiException(
      message: 'Unexpected response format from server',
      statusCode: response.statusCode,
      details: body,
    );
  }

  ApiException _handleDioError(DioException e) {
    if (e.response?.statusCode == 401) {
      tokenStorage.deleteToken();
      onUnauthorized?.call();
    }

    final response = e.response;
    if (response?.data != null && response!.data is Map<String, dynamic>) {
      final data = response.data as Map<String, dynamic>;
      if (data.containsKey('error') && data['error'] != null) {
        final err = data['error'];
        if (err is Map<String, dynamic>) {
          return ApiException(
            message: err['message']?.toString() ?? 'Request failed',
            code: err['code']?.toString(),
            statusCode: response.statusCode,
            details: err,
          );
        } else {
          return ApiException(
            message: err.toString(),
            statusCode: response.statusCode,
          );
        }
      }
    }

    return ApiException(
      message: e.message ?? 'Network connection error',
      code: e.type.name,
      statusCode: response?.statusCode,
      details: response?.data,
    );
  }
}
