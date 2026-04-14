import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:animate_do/animate_do.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart'; 
import '../core/app_constants.dart';

enum OtpPurpose { register, resetPassword }

class OtpScreen extends StatefulWidget {
  final String email;
  final OtpPurpose purpose;
  final VoidCallback onVerified;

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
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  // ── FIX 1: Read Brevo credentials from .env (not hardcoded) ───────────
  // NEVER hardcode API keys in source code.
  // Steps: (1) Add flutter_dotenv to pubspec.yaml
  //        (2) Create .env file in project root (see .env.example)
  //        (3) Add .env to .gitignore
  //        (4) Add assets entry in pubspec.yaml: assets: [.env]
  static String get _brevoApiKey =>
      dotenv.env['BREVO_API_KEY'] ?? '';
  static String get _senderEmail =>
      dotenv.env['BREVO_SENDER_EMAIL'] ?? '';
  static String get _senderName =>
      dotenv.env['BREVO_SENDER_NAME'] ?? 'KNZ Scent';

  String _generatedOtp = '';
  int  _resendSeconds  = 0;
  bool _isVerifying    = false;
  bool _isSending      = true;
  bool _hasError       = false;
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
    for (final c in _controllers) { c.dispose(); }
    for (final f in _focusNodes) { f.dispose(); }
    super.dispose();
  }

  // ── Generate OTP at i-send via Brevo ──────────────────────────────────
  Future<void> _sendOtp({bool resend = false}) async {
    if (!mounted) return;

    // Guard: kung walang API key, ipakita agad ang error
    if (_brevoApiKey.isEmpty) {
      setState(() {
        _isSending = false;
        _hasError  = true;
        _errorMsg  = 'Email service not configured. Contact support.';
      });
      return;
    }

    setState(() {
      _isSending = true;
      _hasError  = false;
      _errorMsg  = null;
      _resendSeconds = 0;
    });

    // Generate 6-digit OTP
    final rng = Random.secure();
    _generatedOtp = List.generate(6, (_) => rng.nextInt(10)).join();

    final purpose = widget.purpose == OtpPurpose.register
        ? 'account registration'
        : 'password reset';

    try {
      final response = await http.post(
        Uri.parse('https://api.brevo.com/v3/smtp/email'),
        headers: {
          'accept':       'application/json',
          'api-key':      _brevoApiKey,   // ← FIX 1: from .env
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'sender': {
            'name':  _senderName,         // ← FIX 1: from .env
            'email': _senderEmail,        // ← FIX 1: from .env
          },
          'to': [
            {'email': widget.email}
          ],
          'subject': 'Your KNZ Scent OTP Code',
          'htmlContent': '''
<!DOCTYPE html>
<html>
<body style="font-family: Arial, sans-serif; background-color: #1a1a1a; margin: 0; padding: 20px;">
  <div style="max-width: 480px; margin: 0 auto; background-color: #242424; border-radius: 16px; padding: 32px; border: 1px solid #333;">
    <div style="text-align: center; margin-bottom: 24px;">
      <h1 style="color: #C9A84C; font-size: 24px; margin: 0; letter-spacing: 2px;">KNZ SCENT</h1>
      <p style="color: #888; font-size: 12px; margin: 4px 0 0;">LUXURY FRAGRANCE HOUSE</p>
    </div>
    <div style="text-align: center; margin-bottom: 24px;">
      <p style="color: #ffffff; font-size: 16px; margin: 0;">Your OTP code for <strong style="color: #C9A84C;">$purpose</strong>:</p>
    </div>
    <div style="background-color: #1a1a1a; border: 2px solid #C9A84C; border-radius: 12px; padding: 20px; text-align: center; margin-bottom: 24px;">
      <h2 style="color: #C9A84C; font-size: 40px; letter-spacing: 12px; margin: 0; font-weight: 800;">$_generatedOtp</h2>
    </div>
    <div style="text-align: center;">
      <p style="color: #888; font-size: 13px; margin: 0;">⏱ Valid for <strong style="color: #fff;">10 minutes</strong> only.</p>
      <p style="color: #888; font-size: 12px; margin: 8px 0 0;">Do not share this code with anyone.</p>
    </div>
    <div style="border-top: 1px solid #333; margin-top: 24px; padding-top: 16px; text-align: center;">
      <p style="color: #555; font-size: 11px; margin: 0;">This email was sent to ${widget.email}</p>
      <p style="color: #555; font-size: 11px; margin: 4px 0 0;">© KNZ Scent — Luxury Fragrance House</p>
    </div>
  </div>
</body>
</html>
          ''',
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 201) {
        setState(() => _isSending = false);
        _startResendTimer();
        _showSnack('OTP sent to ${widget.email}', isError: false);
      } else {
        final body = jsonDecode(response.body);
        setState(() {
          _isSending = false;
          _hasError  = true;
          _errorMsg  = body['message'] ?? 'Failed to send OTP. Please try again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _hasError  = true;
        _errorMsg  = 'No internet connection. Please check and try again.';
      });
    }
  }

  // ── Verify OTP ────────────────────────────────────────────────────────
  void _verify() async {
    if (_enteredOtp.length < 6) {
      setState(() {
        _hasError = true;
        _errorMsg = 'Please enter the complete 6-digit OTP.';
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _hasError    = false;
      _errorMsg    = null;
    });

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    if (_enteredOtp == _generatedOtp) {
      setState(() => _isVerifying = false);
      Navigator.pop(context);
      widget.onVerified();
    } else {
      setState(() {
        _isVerifying = false;
        _hasError    = true;
        _errorMsg    = 'Invalid OTP. Please check your email and try again.';
      });
      for (final c in _controllers) { c.clear(); }
      _focusNodes.first.requestFocus();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────
  String get _enteredOtp => _controllers.map((c) => c.text).join();

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendSeconds = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor:
          isError ? AppColors.error : AppColors.surfaceElevated,
      duration: const Duration(seconds: 4),
      content: Row(children: [
        Icon(
          isError ? Icons.error_outline : Icons.mark_email_read_outlined,
          color: isError ? AppColors.white : AppColors.gold,
          size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(msg,
              style: const TextStyle(color: AppColors.white, fontSize: 13)),
        ),
      ]),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final title = widget.purpose == OtpPurpose.register
        ? 'Verify Your Email'
        : 'Verify Identity';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
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
                            width: 2),
                      ),
                      child: const Icon(Icons.mark_email_unread_outlined,
                          color: AppColors.gold, size: 28),
                    ),
                    const SizedBox(height: 16),
                    Text(title,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        )),
                    const SizedBox(height: 6),
                    const Text('We sent a 6-digit code to',
                        style: TextStyle(
                            color: AppColors.whiteTertiary, fontSize: 12)),
                    Text(widget.email,
                        style: const TextStyle(
                            color: AppColors.gold,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 24),

                    if (_isSending)
                      const Column(children: [
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                              color: AppColors.gold, strokeWidth: 2.5),
                        ),
                        SizedBox(height: 10),
                        Text('Sending OTP to your email...',
                            style: TextStyle(
                                color: AppColors.whiteTertiary,
                                fontSize: 13)),
                      ])
                    else ...[
                      LayoutBuilder(builder: (ctx, constraints) {
                        final boxSize =
                            ((constraints.maxWidth - 8.0 * 6) / 6)
                                .clamp(36.0, 52.0);
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                              6, (i) => _buildOtpBox(i, boxSize)),
                        );
                      }),

                      if (_hasError && _errorMsg != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.error.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline,
                                  color: AppColors.error, size: 14),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_errorMsg!,
                                    style: const TextStyle(
                                        color: AppColors.error, fontSize: 12)),
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
                                        strokeWidth: 2))
                                : const Text('VERIFY OTP',
                                    style: TextStyle(
                                      color: AppColors.background,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.5,
                                      fontSize: 14,
                                    )),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (_resendSeconds > 0)
                        Text('Resend OTP in ${_resendSeconds}s',
                            style: const TextStyle(
                                color: AppColors.whiteTertiary,
                                fontSize: 13))
                      else
                        GestureDetector(
                          onTap: () {
                            for (final c in _controllers) { c.clear(); }
                            setState(() {
                              _hasError = false;
                              _errorMsg = null;
                            });
                            _sendOtp(resend: true);
                          },
                          child: const Text('Resend OTP',
                              style: TextStyle(
                                color: AppColors.gold,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              )),
                        ),
                    ],

                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Text('← Go back',
                          style: TextStyle(
                              color: AppColors.whiteTertiary,
                              fontSize: 12)),
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
                color: _hasError ? AppColors.error : AppColors.cardBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
                color: _hasError ? AppColors.error : AppColors.cardBorder),
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
