// ─────────────────────────────────────────────────────────────────────────────
// otp_screen.dart
// Purpose : Legacy server-side OTP verification screen retained for emulator tests.
// Function: Requests a server-generated OTP challenge from Firebase, then displays
//           six individual digit input boxes. Auto-advances focus to the next
//           box on each digit entry and auto-submits when all 6 digits are filled.
//           Verification, expiry, attempt limits, and one-time token consumption
//           are enforced by Cloud Functions before the callback can run. Production
//           account registration and password reset use Firebase Auth email links.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:animate_do/animate_do.dart';
import '../core/app_constants.dart';
import '../services/otp_service.dart';
import '../widgets/shared_widgets.dart';

enum OtpPurpose { resetPassword }

typedef OtpVerifiedCallback = Future<void> Function(String verificationToken);

class OtpScreen extends StatefulWidget {
  final String email;
  final OtpPurpose purpose;
  final OtpVerifiedCallback onVerified;

  const OtpScreen({
    super.key,
    required this.email,
    required this.purpose,
    required this.onVerified,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  String? _challengeId;
  DateTime? _challengeExpiresAt;
  int _resendSeconds = 0;
  bool _isVerifying = false;
  bool _isSending = true;
  bool _hasError = false;
  String? _errorMsg;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sendOtp();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _purposeValue => 'resetPassword';

  // The server generates and hashes the OTP. The client receives only a random
  // challenge ID and never has a copy of the expected code.
  Future<void> _sendOtp({bool resend = false}) async {
    if (!mounted) return;

    setState(() {
      _isSending = true;
      _hasError = false;
      _errorMsg = null;
      _resendSeconds = 0;
    });

    final result = await OtpService.instance.requestOtp(
      email: widget.email,
      purpose: _purposeValue,
    );

    if (!mounted) return;

    if (result.success) {
      for (final controller in _controllers) {
        controller.clear();
      }
      setState(() {
        _challengeId = result.challengeId;
        _challengeExpiresAt = DateTime.now().add(
          Duration(seconds: result.expiresInSeconds ?? 600),
        );
        _isSending = false;
      });
      _startResendTimer(result.cooldownSeconds ?? 60);
      _showSnack('OTP sent to ${widget.email}', isError: false);
    } else {
      setState(() {
        _isSending = false;
        _hasError = true;
        _errorMsg = result.error ?? 'Failed to send OTP. Please try again.';
      });
      if ((result.retryAfterSeconds ?? 0) > 0) {
        _startResendTimer(result.retryAfterSeconds!);
      }
    }
  }

  // Verification and token consumption both happen on the trusted server. Only
  // then is the short-lived token passed into the legacy callback.
  Future<void> _verify() async {
    if (_isVerifying) return;
    if (_enteredOtp.length < 6) {
      setState(() {
        _hasError = true;
        _errorMsg = 'Please enter the complete 6-digit OTP.';
      });
      return;
    }

    final challengeId = _challengeId;
    if (challengeId == null) {
      setState(() {
        _hasError = true;
        _errorMsg = 'Request a new OTP before verifying.';
      });
      return;
    }
    if (_challengeExpiresAt?.isBefore(DateTime.now()) ?? false) {
      setState(() {
        _hasError = true;
        _errorMsg = 'The OTP has expired. Request a new code.';
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _hasError = false;
      _errorMsg = null;
    });

    final result = await OtpService.instance.verifyOtp(
      challengeId: challengeId,
      otp: _enteredOtp,
    );
    if (!mounted) return;

    final verificationToken = result.verificationToken;
    if (!result.success || verificationToken == null) {
      setState(() {
        _isVerifying = false;
        _hasError = true;
        _errorMsg =
            result.error ??
            'Invalid OTP. Please check your email and try again.';
      });
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes.first.requestFocus();
      return;
    }

    try {
      // The action callback passes this short-lived token to a backend-owned
      // account action; the client never treats OTP verification as authority.
      // atomically. A client-only consume step would not secure either action.
      await widget.onVerified(verificationToken);
      if (mounted) {
        setState(() => _isVerifying = false);
        Navigator.pop(context);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _hasError = true;
        _errorMsg =
            'Verification succeeded, but the account update failed. '
            'Please request a new code and try again.';
      });
    }
  }

  // Joins the 6 individual digit controller values into a single OTP string
  String get _enteredOtp => _controllers.map((c) => c.text).join();

  void _startResendTimer(int seconds) {
    _timer?.cancel();
    setState(() => _resendSeconds = seconds.clamp(1, 3600).toInt());
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_resendSeconds > 0) {
          _resendSeconds--;
        } else {
          t.cancel();
        }
      });
    });
  }

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
    if (isError) {
      KnzToast.error(context, msg);
    } else {
      KnzToast.info(context, msg);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    const title = 'Verify Identity';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: FadeInUp(
              duration: const Duration(milliseconds: 500),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 440),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.gold.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.gold.withValues(alpha: 0.4),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.mark_email_unread_outlined,
                        color: AppColors.gold,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'We sent a 6-digit code to',
                      style: TextStyle(
                        color: AppColors.whiteTertiary,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      widget.email,
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (_isSending)
                      const Column(
                        children: [
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              color: AppColors.gold,
                              strokeWidth: 2.5,
                            ),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Sending OTP to your email...',
                            style: TextStyle(
                              color: AppColors.whiteTertiary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      )
                    else ...[
                      LayoutBuilder(
                        builder: (ctx, constraints) {
                          final boxSize = ((constraints.maxWidth - 8.0 * 6) / 6)
                              .clamp(36.0, 52.0);
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              6,
                              (i) => _buildOtpBox(i, boxSize),
                            ),
                          );
                        },
                      ),

                      if (_hasError && _errorMsg != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.error.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: AppColors.error,
                                size: 14,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMsg!,
                                  style: const TextStyle(
                                    color: AppColors.error,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        child: GestureDetector(
                          onTap: _isVerifying ? null : _verify,
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                              gradient: _isVerifying
                                  ? null
                                  : AppColors.goldGradient,
                              color: _isVerifying
                                  ? AppColors.gold.withValues(alpha: 0.4)
                                  : null,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: _isVerifying
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: AppColors.background,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'VERIFY OTP',
                                    style: TextStyle(
                                      color: AppColors.background,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.5,
                                      fontSize: 14,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (_resendSeconds > 0)
                        Text(
                          'Resend OTP in ${_resendSeconds}s',
                          style: const TextStyle(
                            color: AppColors.whiteTertiary,
                            fontSize: 13,
                          ),
                        )
                      else
                        GestureDetector(
                          onTap: () {
                            for (final c in _controllers) {
                              c.clear();
                            }
                            setState(() {
                              _hasError = false;
                              _errorMsg = null;
                            });
                            _sendOtp(resend: true);
                          },
                          child: const Text(
                            'Resend OTP',
                            style: TextStyle(
                              color: AppColors.gold,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],

                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Text(
                        '← Go back',
                        style: TextStyle(
                          color: AppColors.whiteTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOtpBox(int index, double size) {
    return Container(
      width: size,
      height: size * 1.15,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        maxLength: 1,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: TextStyle(
          color: AppColors.gold,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: _hasError
              ? AppColors.error.withValues(alpha: 0.08)
              : AppColors.inputFill,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: _hasError ? AppColors.error : AppColors.cardBorder,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: _hasError ? AppColors.error : AppColors.cardBorder,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: _hasError ? AppColors.error : AppColors.gold,
              width: 2,
            ),
          ),
        ),
        onChanged: (value) {
          setState(() => _hasError = false);
          if (value.isNotEmpty && index < 5) {
            _focusNodes[index + 1].requestFocus();
          } else if (value.isEmpty && index > 0) {
            _focusNodes[index - 1].requestFocus();
          }
          if (_enteredOtp.length == 6) _verify();
        },
      ),
    );
  }
}
