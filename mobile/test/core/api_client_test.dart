import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/storage/token_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TokenStorage tokenStorage;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    tokenStorage = TokenStorage();
  });

  group('ApiClient Tests', () {
    test('Configures custom baseUrl and default headers', () {
      final client = ApiClient(
        tokenStorage: tokenStorage,
        baseUrl: 'https://api.pair.test/v1',
      );

      expect(client.dio.options.baseUrl, 'https://api.pair.test/v1');
      expect(client.dio.options.headers['Content-Type'], 'application/json');
      expect(client.dio.options.headers['Accept'], 'application/json');
    });

    test('Injects Bearer token into request headers when token is stored', () async {
      await tokenStorage.saveToken('secure-test-token-456');

      final dio = Dio();
      final client = ApiClient(
        tokenStorage: tokenStorage,
        customDio: dio,
      );

      // Add a test interceptor that intercepts the request and asserts headers
      RequestOptions? capturedOptions;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedOptions = options;
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'data': {'id': '1'}, 'meta': null, 'error': null},
              ),
            );
          },
        ),
      );

      final response = await client.get<Map<String, dynamic>>('/test');

      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.headers['Authorization'], 'Bearer secure-test-token-456');
      expect(response.data['id'], '1');
    });

    test('Does not attach Authorization header when token is absent', () async {
      final dio = Dio();
      final client = ApiClient(
        tokenStorage: tokenStorage,
        customDio: dio,
      );

      RequestOptions? capturedOptions;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedOptions = options;
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'data': 'ok', 'meta': null, 'error': null},
              ),
            );
          },
        ),
      );

      final response = await client.get<String>('/test');

      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.headers.containsKey('Authorization'), isFalse);
      expect(response.data, 'ok');
    });

    test('Unwraps {data, meta, error} envelope into ApiResponse', () async {
      final dio = Dio();
      final client = ApiClient(
        tokenStorage: tokenStorage,
        customDio: dio,
      );

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'data': {'userId': 'usr-1', 'name': 'Alex'},
                  'meta': {'page': 1},
                  'error': null,
                },
              ),
            );
          },
        ),
      );

      final response = await client.get<Map<String, dynamic>>('/users/me');

      expect(response.data['userId'], 'usr-1');
      expect(response.data['name'], 'Alex');
      expect(response.meta?['page'], 1);
    });

    test('Throws ApiException when backend returns error envelope in 200 response', () async {
      final dio = Dio();
      final client = ApiClient(
        tokenStorage: tokenStorage,
        customDio: dio,
      );

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'data': null,
                  'meta': null,
                  'error': {
                    'message': 'Action not permitted',
                    'code': 'FORBIDDEN',
                  },
                },
              ),
            );
          },
        ),
      );

      expect(
        () => client.get<dynamic>('/invalid'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Action not permitted')
              .having((e) => e.code, 'code', 'FORBIDDEN'),
        ),
      );
    });

    test('Handles 401: clears stored token, triggers onUnauthorized, and throws ApiException', () async {
      await tokenStorage.saveToken('expired-token');
      expect(await tokenStorage.hasToken(), isTrue);

      var unauthorizedTriggered = false;
      final dio = Dio();
      final client = ApiClient(
        tokenStorage: tokenStorage,
        customDio: dio,
        onUnauthorized: () {
          unauthorizedTriggered = true;
        },
      );

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 401,
                  data: {
                    'data': null,
                    'meta': null,
                    'error': {
                      'message': 'Unauthorized token',
                      'code': 'UNAUTHORIZED',
                    },
                  },
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      await expectLater(
        () => client.get<dynamic>('/protected'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.code, 'code', 'UNAUTHORIZED')
              .having((e) => e.message, 'message', 'Unauthorized token'),
        ),
      );

      expect(await tokenStorage.hasToken(), isFalse);
      expect(unauthorizedTriggered, isTrue);
    });

    test('Supports POST, PUT, PATCH, DELETE operations', () async {
      final dio = Dio();
      final client = ApiClient(
        tokenStorage: tokenStorage,
        customDio: dio,
      );

      String? capturedMethod;
      dynamic capturedData;

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedMethod = options.method;
            capturedData = options.data;
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'data': {'status': 'success'}, 'meta': null, 'error': null},
              ),
            );
          },
        ),
      );

      // POST
      final postRes = await client.post<Map<String, dynamic>>('/items', data: {'name': 'Goal'});
      expect(capturedMethod, 'POST');
      expect(capturedData, {'name': 'Goal'});
      expect(postRes.data['status'], 'success');

      // PUT
      await client.put<Map<String, dynamic>>('/items/1', data: {'name': 'Updated'});
      expect(capturedMethod, 'PUT');
      expect(capturedData, {'name': 'Updated'});

      // PATCH
      await client.patch<Map<String, dynamic>>('/items/1', data: {'name': 'Patched'});
      expect(capturedMethod, 'PATCH');
      expect(capturedData, {'name': 'Patched'});

      // DELETE
      await client.delete<Map<String, dynamic>>('/items/1');
      expect(capturedMethod, 'DELETE');
    });
  });
}
