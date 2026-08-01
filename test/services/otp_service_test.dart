import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:knz_scent_admin/services/otp_service.dart';

void main() {
  test(
    'requestOtp authenticates the callable request and maps success',
    () async {
      Uri? requestedUrl;
      Map<String, String>? requestedHeaders;
      Object? requestedBody;
      final service = OtpService(
        idTokenProvider: () async => 'firebase-token',
        functionsOrigin: 'https://functions.example.test',
        post: (url, {headers, body}) async {
          requestedUrl = url;
          requestedHeaders = headers;
          requestedBody = body;
          return http.Response(
            jsonEncode({
              'result': {
                'challengeId': 'challenge-1',
                'expiresInSeconds': 300,
                'cooldownSeconds': 45,
              },
            }),
            200,
          );
        },
      );

      final result = await service.requestOtp(
        email: 'staff@example.com',
        purpose: 'register',
      );

      expect(result.success, isTrue);
      expect(result.challengeId, 'challenge-1');
      expect(result.expiresInSeconds, 300);
      expect(result.cooldownSeconds, 45);
      expect(
        requestedUrl,
        Uri.parse('https://functions.example.test/requestOtp'),
      );
      expect(requestedHeaders?['Authorization'], 'Bearer firebase-token');
      expect(requestedHeaders?['Content-Type'], 'application/json');
      expect(jsonDecode(requestedBody! as String), {
        'data': {'email': 'staff@example.com', 'purpose': 'register'},
      });
    },
  );

  test('requestOtp maps safe backend errors and retry details', () async {
    final service = OtpService(
      idTokenProvider: () async => 'firebase-token',
      post: (_, {headers, body}) async => http.Response(
        jsonEncode({
          'error': {
            'message': 'Wait before requesting another code.',
            'details': {'retryAfterSeconds': 37},
          },
        }),
        429,
      ),
    );

    final result = await service.requestOtp(
      email: 'staff@example.com',
      purpose: 'register',
    );

    expect(result.success, isFalse);
    expect(result.error, 'Wait before requesting another code.');
    expect(result.retryAfterSeconds, 37);
  });

  test(
    'requestOtp rejects a successful response without a challenge',
    () async {
      final service = OtpService(
        idTokenProvider: () async => 'firebase-token',
        post: (_, {headers, body}) async =>
            http.Response(jsonEncode({'result': {}}), 200),
      );

      final result = await service.requestOtp(
        email: 'staff@example.com',
        purpose: 'register',
      );

      expect(result.success, isFalse);
      expect(result.error, 'The email service returned an invalid response.');
    },
  );

  test('verifyOtp maps successful tokens and default expiry', () async {
    final service = OtpService(
      idTokenProvider: () async => 'firebase-token',
      post: (_, {headers, body}) async => http.Response(
        jsonEncode({
          'result': {'verificationToken': 'verification-token'},
        }),
        200,
      ),
    );

    final result = await service.verifyOtp(
      challengeId: 'challenge-1',
      otp: '123456',
    );

    expect(result.success, isTrue);
    expect(result.verificationToken, 'verification-token');
    expect(result.expiresInSeconds, 120);
  });

  test('verifyOtp maps failed-attempt details', () async {
    final service = OtpService(
      idTokenProvider: () async => 'firebase-token',
      post: (_, {headers, body}) async => http.Response(
        jsonEncode({
          'error': {
            'message': 'Invalid OTP.',
            'details': {'attemptsRemaining': 2},
          },
        }),
        400,
      ),
    );

    final result = await service.verifyOtp(
      challengeId: 'challenge-1',
      otp: '000000',
    );

    expect(result.success, isFalse);
    expect(result.error, 'Invalid OTP.');
    expect(result.attemptsRemaining, 2);
  });

  test('missing Firebase token prevents any network request', () async {
    var postCalled = false;
    final service = OtpService(
      idTokenProvider: () async => null,
      post: (_, {headers, body}) async {
        postCalled = true;
        return http.Response('{}', 200);
      },
    );

    final result = await service.requestOtp(
      email: 'staff@example.com',
      purpose: 'register',
    );

    expect(result.success, isFalse);
    expect(postCalled, isFalse);
    expect(result.error, contains('Cloud verification is unavailable'));
  });

  test('timeouts return a stable error without exposing internals', () async {
    final service = OtpService(
      idTokenProvider: () async => 'firebase-token',
      timeout: const Duration(milliseconds: 1),
      post: (_, {headers, body}) => Completer<http.Response>().future,
    );

    final result = await service.requestOtp(
      email: 'staff@example.com',
      purpose: 'register',
    );

    expect(result.success, isFalse);
    expect(
      result.error,
      'The verification service timed out. Please try again.',
    );
  });
}
