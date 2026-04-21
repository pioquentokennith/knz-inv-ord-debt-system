// ─────────────────────────────────────────────────────────────────────────────
// register_screen.dart
// Purpose : New account registration screen with OTP email verification.
// Function: Collects full name, username, email, password, and password confirmation.
//           Validates all fields including email format, minimum password length,
//           and password match. Shows a live password strength indicator (Weak /
//           Medium / Strong) based on length, uppercase, digits, and special chars.
//           Navigates to OtpScreen for email verification before calling
//           AppState.register(). On success, navigates to MainShell and clears
//           the navigation stack.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../widgets/shared_widgets.dart';
import 'main_shell.dart';
import 'otp_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _nameCtrl    = TextEditingController();
  final _userCtrl    = TextEditingController();
  final _emailCtrl   = TextEditingController();   // email na, hindi phone
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscurePass    = true;
  bool _obscureConfirm = true;
  bool _isLoading      = false;
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
    _pulse = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _nameCtrl.dispose();
    _userCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // Scores the current password from 0 (empty) to 5 (very strong).
  // Adds 1 point each for: length>=6, length>=10, uppercase letter, digit, special char.
  int get _passwordStrength {
    final p = _passCtrl.text;
    if (p.isEmpty) return 0;
    int score = 0;
    if (p.length >= 6) score++;
    if (p.length >= 10) score++;
    if (p.contains(RegExp(r'[A-Z]'))) score++;
    if (p.contains(RegExp(r'[0-9]'))) score++;
    if (p.contains(RegExp(r'[!@#\$%^&*]'))) score++;
    return score;
  }

  Color get _strengthColor {
    switch (_passwordStrength) {
      case 0:
      case 1: return AppColors.error;
      case 2:
      case 3: return AppColors.warning;
      default: return AppColors.success;
    }
  }

  String get _strengthLabel {
    switch (_passwordStrength) {
      case 0:
      case 1: return 'Weak';
      case 2:
      case 3: return 'Medium';
      default: return 'Strong';
    }
  }

  // Validates all form fields then navigates to OtpScreen.
  // The OTP screen calls _register() in its onVerified callback.
  void _proceed() {
    final name     = _nameCtrl.text.trim();
    final username = _userCtrl.text.trim();
    final email    = _emailCtrl.text.trim();
    final password = _passCtrl.text;
    final confirm  = _confirmCtrl.text;

    if (name.isEmpty || username.isEmpty || email.isEmpty ||
        password.isEmpty || confirm.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    if (!RegExp(r'^[\w\.\+\-]+@[\w\-]+\.\w+$').hasMatch(email)) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() => _error = null);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OtpScreen(
          email: email,
          purpose: OtpPurpose.register,
          onVerified: () => _register(name, username, email, password),
        ),
      ),
    );
  }

  // Called after OTP verification succeeds. Calls AppState.register()
  // to create the account, then navigates to MainShell on success.
  Future<void> _register(
      String name, String username, String email, String password) async {
    setState(() => _isLoading = true);

    final success = await AppState()
        .register(name, username, password, email: email);

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF1E4D2B),
          content: Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 16),
              SizedBox(width: 8),
              Text('Account created! Welcome to ${AppStrings.appName}.',
                  style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainShell()),
        (route) => false,
      );
    } else {
      setState(() {
        _isLoading = false;
        _error = 'Username already exists or registration failed.';
      });
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
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
                      _buildFormPanel(),
                    ]),
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
            const Text(AppStrings.appSubtitle,
                style: AppTextStyles.brandSubtitle),
            const SizedBox(height: 32),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Text(
                '✦  ${AppStrings.luxuryFragranceHouse}  ✦',
                style: TextStyle(
                    color: AppColors.gold, fontSize: 13, letterSpacing: 1.5),
              ),
            ),
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
          const Text(AppStrings.appSubtitle,
              style: AppTextStyles.brandSubtitle),
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
          _ring(size * 1.4,
              AppColors.gold.withValues(alpha: 0.05 * _pulse.value)),
          _ring(size * 1.15,
              AppColors.gold.withValues(alpha: 0.1 * _pulse.value)),
          _ring(size, AppColors.gold.withValues(alpha: 0.15)),
          Container(
            width: size * 0.55,
            height: size * 0.55,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border:
                  Border.all(color: AppColors.gold.withValues(alpha: 0.6)),
            ),
            child: Icon(Icons.person_add_outlined,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: const BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: AppColors.gold, width: 2)),
              ),
              child: const Text(
                'CREATE ACCOUNT',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.gold,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Full Name
            DarkTextField(
              label: 'FULL NAME',
              hint: 'Enter your full name',
              controller: _nameCtrl,
              prefixIcon: Icons.person_outline,
            ),
            const SizedBox(height: 12),

            // Username
            DarkTextField(
              label: 'USERNAME',
              hint: 'Choose a username',
              controller: _userCtrl,
              prefixIcon: Icons.alternate_email,
            ),
            const SizedBox(height: 12),

            // Email (pinalitan ng phone)
            _buildEmailField(),
            const SizedBox(height: 12),

            // Password
            _buildPasswordField(),
            const SizedBox(height: 6),

            if (_passCtrl.text.isNotEmpty) _buildPasswordStrength(),
            const SizedBox(height: 12),

            // Confirm Password
            _buildConfirmField(),

            if (_error != null) ...[
              const SizedBox(height: 10),
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
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.error, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: const TextStyle(
                              color: AppColors.error, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),

            // OTP info banner
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.email_outlined,
                      color: AppColors.gold, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'A 6-digit OTP will be sent to your email for verification.',
                      style:
                          TextStyle(color: AppColors.gold, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            GoldButton(
              label: _isLoading ? '...' : 'SEND OTP & VERIFY',
              onPressed: _isLoading ? () {} : _proceed,
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Center(
                child: Text(
                  'Already have an account? Sign In',
                  style: TextStyle(
                      color: AppColors.whiteTertiary, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Email field ──────────────────────────────────────────────────────
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
          onChanged: (_) => setState(() {}),
          style: const TextStyle(color: AppColors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'example@gmail.com',
            hintStyle: const TextStyle(
                color: AppColors.whiteTertiary, fontSize: 13),
            prefixIcon: const Icon(Icons.email_outlined,
                color: AppColors.whiteTertiary, size: 18),
            filled: true,
            fillColor: AppColors.inputFill,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.gold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('PASSWORD',
            style: TextStyle(
                color: AppColors.whiteTertiary,
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextField(
          controller: _passCtrl,
          obscureText: _obscurePass,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(color: AppColors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Min. 6 characters',
            hintStyle:
                const TextStyle(color: AppColors.whiteTertiary),
            prefixIcon: const Icon(Icons.lock_outline,
                color: AppColors.whiteTertiary, size: 18),
            suffixIcon: GestureDetector(
              onTap: () =>
                  setState(() => _obscurePass = !_obscurePass),
              child: Icon(
                _obscurePass
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AppColors.whiteTertiary,
                size: 18,
              ),
            ),
            filled: true,
            fillColor: AppColors.inputFill,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.gold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordStrength() {
    return Row(
      children: [
        ...List.generate(
          5,
          (i) => Expanded(
            child: Container(
              margin: const EdgeInsets.only(right: 3),
              height: 3,
              decoration: BoxDecoration(
                color: i < _passwordStrength
                    ? _strengthColor
                    : AppColors.cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(_strengthLabel,
            style: TextStyle(
                color: _strengthColor,
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildConfirmField() {
    final matches = _passCtrl.text.isNotEmpty &&
        _confirmCtrl.text.isNotEmpty &&
        _passCtrl.text == _confirmCtrl.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('CONFIRM PASSWORD',
            style: TextStyle(
                color: AppColors.whiteTertiary,
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextField(
          controller: _confirmCtrl,
          obscureText: _obscureConfirm,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(color: AppColors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Re-enter your password',
            hintStyle:
                const TextStyle(color: AppColors.whiteTertiary),
            prefixIcon: const Icon(Icons.lock_outline,
                color: AppColors.whiteTertiary, size: 18),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_confirmCtrl.text.isNotEmpty)
                  Icon(
                    matches ? Icons.check_circle : Icons.cancel,
                    color: matches ? AppColors.success : AppColors.error,
                    size: 16,
                  ),
                GestureDetector(
                  onTap: () => setState(
                      () => _obscureConfirm = !_obscureConfirm),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12, left: 4),
                    child: Icon(
                      _obscureConfirm
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AppColors.whiteTertiary,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
            filled: true,
            fillColor: AppColors.inputFill,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: _confirmCtrl.text.isNotEmpty
                    ? (matches ? AppColors.success : AppColors.error)
                    : AppColors.cardBorder,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: _confirmCtrl.text.isNotEmpty
                    ? (matches ? AppColors.success : AppColors.error)
                    : AppColors.cardBorder,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.gold),
            ),
          ),
        ),
      ],
    );
  }
}
