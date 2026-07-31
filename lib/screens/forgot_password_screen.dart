import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../widgets/shared_widgets.dart';

typedef PasswordResetRequester = Future<void> Function(String email);

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.sendPasswordReset});

  final PasswordResetRequester? sendPasswordReset;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await (widget.sendPasswordReset ?? AppState().sendPasswordReset)(email);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _submitted = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error =
            'Password-reset instructions could not be sent. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Reset password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: _submitted ? _buildConfirmation() : _buildForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.lock_reset, color: AppColors.gold, size: 52),
        const SizedBox(height: 18),
        const Text(
          'PASSWORD RECOVERY',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.gold,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Enter your account email. If an account is eligible, Firebase will send password-reset instructions.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.whiteSecondary),
        ),
        const SizedBox(height: 24),
        DarkTextField(
          label: 'EMAIL ADDRESS',
          hint: 'name@example.com',
          controller: _emailController,
          prefixIcon: Icons.email_outlined,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.error)),
        ],
        const SizedBox(height: 20),
        GoldButton(
          label: _isLoading ? 'SENDING...' : 'SEND RESET INSTRUCTIONS',
          onPressed: _isLoading ? () {} : _submit,
        ),
      ],
    );
  }

  Widget _buildConfirmation() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.mark_email_read_outlined,
          color: AppColors.success,
          size: 58,
        ),
        const SizedBox(height: 18),
        const Text(
          'Check your email',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        const Text(
          'If an eligible account matches that address, password-reset instructions have been sent.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.whiteSecondary),
        ),
        const SizedBox(height: 24),
        GoldButton(
          label: 'BACK TO SIGN IN',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
