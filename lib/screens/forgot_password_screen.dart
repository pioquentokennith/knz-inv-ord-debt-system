// ─────────────────────────────────────────────────────────────────────────────
// forgot_password_screen.dart
// Purpose : Allows an existing user to reset their password via OTP verification.
// Function: Collects username, email, new password, and confirmation. Validates
//           all fields (email format, password length, password match) before
//           navigating to OtpScreen for email verification. Once the OTP is
//           confirmed, calls AppState.resetPassword() to update the stored password.
//           Shows a success view with a "Back to Sign In" button on completion.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../widgets/shared_widgets.dart';
import 'otp_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _userCtrl    = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscureNew     = true;
  bool _obscureConfirm = true;
  bool _isLoading      = false;
  bool _success        = false;
  String? _error;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.8, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _userCtrl.dispose();
    _emailCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // Validates all fields then navigates to OtpScreen for email verification.
  // The OTP screen calls _resetPassword() in its onVerified callback.
  void _proceed() {
    final username = _userCtrl.text.trim();
    final email    = _emailCtrl.text.trim();
    final newPass  = _newPassCtrl.text.trim();
    final confirm  = _confirmCtrl.text.trim();

    if (username.isEmpty || email.isEmpty || newPass.isEmpty || confirm.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    if (!RegExp(r'^[\w\.\+\-]+@[\w\-]+\.\w+$').hasMatch(email)) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    if (newPass.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (newPass != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() => _error = null);

    // Navigate to OTP verification
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OtpScreen(
          email: email,
          purpose: OtpPurpose.resetPassword,
          onVerified: () => _resetPassword(username, newPass),
        ),
      ),
    );
  }

  // Called after OTP verification. Updates the stored password via AppState.
  // Shows a success view on completion or an error message if username not found.
  Future<void> _resetPassword(String username, String newPass) async {
    setState(() => _isLoading = true);
    final success = await AppState().resetPassword(username, newPass);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (success) {
        _success = true;
      } else {
        _error = 'Username not found. Please check and try again.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: FadeInUp(
              duration: const Duration(milliseconds: 600),
              child: Container(
                width: isWide ? 750 : double.infinity,
                constraints: const BoxConstraints(maxWidth: 750),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.cardBorder),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.gold.withValues(alpha: 0.05),
                      blurRadius: 40,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: isWide
                    ? Row(children: [_buildBrandPanel(), _buildFormPanel()])
                    : Column(children: [
                        _buildBrandPanelMobile(),
                        _buildFormPanel()
                      ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandPanel() {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(48),
        decoration: const BoxDecoration(
          gradient: AppColors.sidebarGradient,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            bottomLeft: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildPulsingLogo(),
            const SizedBox(height: 32),
            const Text(AppStrings.appName, style: AppTextStyles.brandName),
            const SizedBox(height: 4),
            const Text(AppStrings.appSubtitle, style: AppTextStyles.brandSubtitle),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandPanelMobile() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: const BoxDecoration(
        gradient: AppColors.sidebarGradient,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          _buildPulsingLogo(size: 80),
          const SizedBox(height: 16),
          Text(AppStrings.appName,
              style: AppTextStyles.brandName.copyWith(fontSize: 26)),
          const SizedBox(height: 4),
          const Text(AppStrings.appSubtitle, style: AppTextStyles.brandSubtitle),
        ],
      ),
    );
  }

  Widget _buildPulsingLogo({double size = 110}) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Stack(
        alignment: Alignment.center,
        children: [
          _ring(size * 1.4, AppColors.gold.withValues(alpha: 0.05 * _pulse.value)),
          _ring(size * 1.15, AppColors.gold.withValues(alpha: 0.1 * _pulse.value)),
          _ring(size, AppColors.gold.withValues(alpha: 0.15)),
          Container(
            width: size * 0.55,
            height: size * 0.55,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.6)),
            ),
            child: Icon(Icons.lock_reset_outlined,
                color: AppColors.gold, size: size * 0.28),
          ),
        ],
      ),
    );
  }

  Widget _ring(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.5),
        ),
      );

  Widget _buildFormPanel() {
    final isWide = MediaQuery.of(context).size.width > 700;
    return Expanded(
      flex: isWide ? 1 : 0,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: _success ? _buildSuccessView() : _buildFormView(),
      ),
    );
  }

  Widget _buildSuccessView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_outline,
            color: AppColors.success, size: 64),
        const SizedBox(height: 20),
        const Text('Password Reset!',
            style: TextStyle(
                color: AppColors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text(
          'Your password has been successfully updated. You can now sign in with your new password.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.whiteSecondary, fontSize: 13),
        ),
        const SizedBox(height: 28),
        GoldButton(
          label: 'BACK TO SIGN IN',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildFormView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.gold, width: 2)),
          ),
          child: const Text(
            'RESET PASSWORD',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.gold,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter your username and email address to verify your identity.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.whiteTertiary, fontSize: 12),
        ),
        const SizedBox(height: 20),

        // Username
        DarkTextField(
          label: 'USERNAME',
          hint: 'Enter your username',
          controller: _userCtrl,
          prefixIcon: Icons.alternate_email,
        ),
        const SizedBox(height: 12),

        // Email Address
        _buildEmailField(),
        const SizedBox(height: 12),

        // New Password
        _buildPasswordField(
          label: 'NEW PASSWORD',
          ctrl: _newPassCtrl,
          obscure: _obscureNew,
          onToggle: () => setState(() => _obscureNew = !_obscureNew),
        ),
        const SizedBox(height: 12),

        // Confirm Password
        _buildPasswordField(
          label: 'CONFIRM NEW PASSWORD',
          ctrl: _confirmCtrl,
          hint: 'Re-enter new password',
          obscure: _obscureConfirm,
          onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
        ),

        if (_error != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.error, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_error!,
                      style: const TextStyle(color: AppColors.error, fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),

        // OTP info banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.sms_outlined, color: AppColors.gold, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'A 6-digit OTP will be sent to your email to verify your identity.',
                  style: TextStyle(color: AppColors.gold, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        GoldButton(
          label: _isLoading ? '...' : 'SEND OTP & RESET',
          onPressed: _isLoading ? () {} : _proceed,
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Center(
            child: Text(
              '← Back to Sign In',
              style: TextStyle(color: AppColors.whiteTertiary, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('EMAIL ADDRESS',
            style: TextStyle(
                color: AppColors.whiteTertiary,
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: AppColors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'example@gmail.com',
            hintStyle: const TextStyle(color: AppColors.whiteTertiary, fontSize: 13),
            prefixIcon: const Icon(Icons.email_outlined, color: AppColors.whiteTertiary, size: 18),
            filled: true,
            fillColor: AppColors.inputFill,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.cardBorder)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.cardBorder)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.gold)),
          ),
        ),
      ],
    );
  }

  
  Widget _buildPasswordField({
    required String label,
    required TextEditingController ctrl,
    required bool obscure,
    required VoidCallback onToggle,
    String hint = 'Min. 6 characters',
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.whiteTertiary,
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          obscureText: obscure,
          style: const TextStyle(color: AppColors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.whiteTertiary),
            prefixIcon:
                const Icon(Icons.lock_outline, color: AppColors.whiteTertiary, size: 18),
            suffixIcon: GestureDetector(
              onTap: onToggle,
              child: Icon(
                obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: AppColors.whiteTertiary,
                size: 18,
              ),
            ),
            filled: true,
            fillColor: AppColors.inputFill,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.cardBorder)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.cardBorder)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.gold)),
          ),
        ),
      ],
    );
  }
}
