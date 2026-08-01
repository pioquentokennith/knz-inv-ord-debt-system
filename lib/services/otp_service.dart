import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

typedef OtpIdTokenProvider = Future<String?> Function();
typedef OtpHttpPost =
    Future<http.Response> Function(
      Uri url, {
      Map<String, String>? headers,
      Object? body,
    });

/// Calls the Firebase callable OTP endpoints without placing email-provider
/// credentials or OTP generation logic in the app binary.
class OtpService {
  OtpService({
    OtpIdTokenProvider? idTokenProvider,
    OtpHttpPost? post,
    String functionsOrigin = _defaultFunctionsOrigin,
    Duration timeout = const Duration(seconds: 20),
  }) : _idTokenProvider = idTokenProvider ?? _firebaseIdToken,
       _post =
           post ??
           ((url, {headers, body}) =>
               http.post(url, headers: headers, body: body)),
       _functionsOrigin = functionsOrigin,
       _timeout = timeout;

  static final instance = OtpService();

  final OtpIdTokenProvider _idTokenProvider;
  final OtpHttpPost _post;
  final String _functionsOrigin;
  final Duration _timeout;

  static const String _defaultFunctionsOrigin = String.fromEnvironment(
    'OTP_FUNCTIONS_ORIGIN',
    defaultValue: 'https://us-central1-knz-scent.cloudfunctions.net',
  );

  Future<OtpChallengeResult> requestOtp({
    required String email,
    required String purpose,
  }) async {
    final response = await _call('requestOtp', {
      'email': email,
      'purpose': purpose,
    });
    if (!response.success) {
      return OtpChallengeResult(
        success: false,
        error: response.error,
        retryAfterSeconds: _asInt(response.details?['retryAfterSeconds']),
      );
    }
    final challengeId = response.result?['challengeId'];
    if (challengeId is! String || challengeId.isEmpty) {
      return const OtpChallengeResult(
        success: false,
        error: 'The email service returned an invalid response.',
      );
    }
    return OtpChallengeResult(
      success: true,
      challengeId: challengeId,
      expiresInSeconds: _asInt(response.result?['expiresInSeconds']) ?? 600,
      cooldownSeconds: _asInt(response.result?['cooldownSeconds']) ?? 60,
    );
  }

  Future<OtpVerificationResult> verifyOtp({
    required String challengeId,
    required String otp,
  }) async {
    final response = await _call('verifyOtp', {
      'challengeId': challengeId,
      'otp': otp,
    });
    if (!response.success) {
      return OtpVerificationResult(
        success: false,
        error: response.error,
        attemptsRemaining: _asInt(response.details?['attemptsRemaining']),
      );
    }
    final verificationToken = response.result?['verificationToken'];
    if (verificationToken is! String || verificationToken.isEmpty) {
      return const OtpVerificationResult(
        success: false,
        error: 'The verification service returned an invalid response.',
      );
    }
    return OtpVerificationResult(
      success: true,
      verificationToken: verificationToken,
      expiresInSeconds: _asInt(response.result?['expiresInSeconds']) ?? 120,
    );
  }

  Future<_CallableResponse> _call(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    try {
      final idToken = await _idTokenProvider().timeout(_timeout);
      if (idToken == null || idToken.isEmpty) {
        return const _CallableResponse(
          success: false,
          error:
              'Cloud verification is unavailable. Reconnect and restart the app.',
        );
      }

      final response = await _post(
        Uri.parse('$_functionsOrigin/$functionName'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'data': data}),
      ).timeout(_timeout);

      Map<String, dynamic> body;
      try {
        final decoded = jsonDecode(response.body);
        body = decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};
      } on FormatException {
        return const _CallableResponse(
          success: false,
          error: 'The verification service returned an invalid response.',
        );
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final result = body['result'];
        return _CallableResponse(
          success: true,
          result: result is Map ? Map<String, dynamic>.from(result) : const {},
        );
      }

      final error = body['error'];
      final errorMap = error is Map
          ? Map<String, dynamic>.from(error)
          : const <String, dynamic>{};
      final details = errorMap['details'];
      return _CallableResponse(
        success: false,
        error: _safeErrorMessage(errorMap['message']),
        details: details is Map ? Map<String, dynamic>.from(details) : null,
      );
    } on TimeoutException {
      return const _CallableResponse(
        success: false,
        error: 'The verification service timed out. Please try again.',
      );
    } catch (_) {
      return const _CallableResponse(
        success: false,
        error: 'No internet connection. Please check and try again.',
      );
    }
  }

  static Future<String?> _firebaseIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    return user?.getIdToken();
  }

  static int? _asInt(dynamic value) => value is num ? value.toInt() : null;

  static String _safeErrorMessage(dynamic value) {
    if (value is String && value.isNotEmpty && value.length <= 240) {
      return value;
    }
    return 'Email verification failed. Please try again.';
  }
}

class OtpChallengeResult {
  final bool success;
  final String? challengeId;
  final int? expiresInSeconds;
  final int? cooldownSeconds;
  final int? retryAfterSeconds;
  final String? error;

  const OtpChallengeResult({
    required this.success,
    this.challengeId,
    this.expiresInSeconds,
    this.cooldownSeconds,
    this.retryAfterSeconds,
    this.error,
  });
}

class OtpVerificationResult {
  final bool success;
  final String? verificationToken;
  final int? expiresInSeconds;
  final int? attemptsRemaining;
  final String? error;

  const OtpVerificationResult({
    required this.success,
    this.verificationToken,
    this.expiresInSeconds,
    this.attemptsRemaining,
    this.error,
  });
}

class _CallableResponse {
  final bool success;
  final Map<String, dynamic>? result;
  final Map<String, dynamic>? details;
  final String? error;

  const _CallableResponse({
    required this.success,
    this.result,
    this.details,
    this.error,
  });
}
