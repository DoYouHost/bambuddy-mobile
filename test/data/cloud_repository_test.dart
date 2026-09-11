import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/data/cloud_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late CloudRepository repo;

  setUp(() {
    dio = testDio();
    adapter = DioAdapter(dio: dio);
    repo = CloudRepository(dio);
  });

  group('CloudRepository', () {
    test('status decodes authenticated cloud user', () async {
      adapter.onGet(
        Endpoints.cloudStatus,
        (s) => s.reply(200, {
          'is_authenticated': true,
          'email': 'user@example.com',
          'region': 'global',
        }),
      );

      final status = await repo.status();
      expect(status.isAuthenticated, isTrue);
      expect(status.email, 'user@example.com');
      expect(status.region, 'global');
    });

    test('status handles logged out state and empty payload', () async {
      adapter.onGet(
        Endpoints.cloudStatus,
        (s) => s.reply(200, <String, dynamic>{}),
      );

      final status = await repo.status();
      expect(status.isAuthenticated, isFalse);
      expect(status.email, isNull);
      expect(status.region, isNull);
    });

    test('login succeeds without 2FA', () async {
      adapter.onPost(
        Endpoints.cloudLogin,
        (s) => s.reply(200, {
          'success': true,
          'needs_verification': false,
          'message': 'Logged in successfully',
        }),
        data: {
          'email': 'user@example.com',
          'password': 'secretPassword',
          'region': 'global',
        },
      );

      final result = await repo.login(
        email: 'user@example.com',
        password: 'secretPassword',
      );

      expect(result.success, isTrue);
      expect(result.needsVerification, isFalse);
      expect(result.message, 'Logged in successfully');
    });

    test('login signals 2FA challenge with verification type and tfa_key', () async {
      adapter.onPost(
        Endpoints.cloudLogin,
        (s) => s.reply(200, {
          'success': false,
          'needs_verification': true,
          'verification_type': 'email',
          'tfa_key': 'tfa-token-xyz',
          'message': 'Check your inbox for code',
        }),
        data: {
          'email': 'user@example.com',
          'password': 'secretPassword',
          'region': 'china',
        },
      );

      final result = await repo.login(
        email: 'user@example.com',
        password: 'secretPassword',
        region: 'china',
      );

      expect(result.success, isFalse);
      expect(result.needsVerification, isTrue);
      expect(result.verificationType, 'email');
      expect(result.tfaKey, 'tfa-token-xyz');
      expect(result.message, 'Check your inbox for code');
    });

    test('verify sends 2FA code and tfaKey', () async {
      adapter.onPost(
        Endpoints.cloudVerify,
        (s) => s.reply(200, {
          'success': true,
          'needs_verification': false,
          'message': '2FA passed',
        }),
        data: {
          'email': 'user@example.com',
          'code': '123456',
          'tfa_key': 'tfa-token-xyz',
          'region': 'global',
        },
      );

      final result = await repo.verify(
        email: 'user@example.com',
        code: '123456',
        tfaKey: 'tfa-token-xyz',
      );

      expect(result.success, isTrue);
      expect(result.needsVerification, isFalse);
    });

    test('logout posts to cloud logout endpoint', () async {
      adapter.onPost(
        Endpoints.cloudLogout,
        (s) => s.reply(200, {'success': true}),
      );

      await expectLater(repo.logout(), completes);
    });

    test('maps 401 DioException to AuthException', () async {
      adapter.onGet(
        Endpoints.cloudStatus,
        (s) => s.reply(401, {'detail': 'Token expired'}),
      );

      expect(
        () => repo.status(),
        throwsA(isA<AuthException>()),
      );
    });

    test('maps 500 DioException to ApiException', () async {
      adapter.onPost(
        Endpoints.cloudLogout,
        (s) => s.reply(500, {'detail': 'Server error'}),
      );

      expect(
        () => repo.logout(),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
