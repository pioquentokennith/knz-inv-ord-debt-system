// ─────────────────────────────────────────────────────────────────────────────
// login_screen.dart
// Purpose : The entry point screen where users authenticate with username & password.
// Function: Renders a two-panel layout (brand panel + form panel) on wide screens,
//           and a stacked layout on narrow screens. A pulsing gold logo animation
//           plays continuously via AnimationController. On submit, calls
//           AppState.login() and navigates to MainShell on success or shows an
//           error message on failure. Also provides links to RegisterScreen and
//           ForgotPasswordScreen.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'dart:async';
import '../core/app_bootstrap.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../services/login_rate_limiter.dart';
import '../widgets/shared_widgets.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.bootstrap});

  final AppBootstrap bootstrap;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isLoading = false;
  String? _error;

  // ── Rate-limit countdown ───────────────────────────────────────────────────
  // When the user is locked out, _lockoutSeconds counts down to 0 and
  // the login button is disabled with a live "Try again in Xs" label.
  int _lockoutSeconds = 0;
  Timer? _lockoutTimer;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulse = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  // Starts a 1-second tick that updates the lockout countdown label.
  void _startLockoutCountdown(int seconds) {
    _lockoutTimer?.cancel();
    setState(() => _lockoutSeconds = seconds);
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final remaining = LoginRateLimiter.instance.secondsRemaining(
        _userCtrl.text.trim(),
      );
      setState(() => _lockoutSeconds = remaining);
      if (remaining <= 0) {
        t.cancel();
        setState(() => _error = null); // Clear the lockout message
      }
    });
  }

  // Calls AppState.login() with the entered credentials.
  // On success, navigates to MainShell with a fade transition.
  // On failure, records the attempt and shows error or lockout message.
  void _login() async {
    final email = _userCtrl.text.trim().toLowerCase();
    final limiter = LoginRateLimiter.instance;

    // ── Check lockout before even calling AppState ─────────────────────────
    if (limiter.isLockedOut(email)) {
      final secs = limiter.secondsRemaining(email);
      _startLockoutCountdown(secs);
      setState(
        () => _error = 'Too many failed attempts. Try again in ${secs}s.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final firebaseReady = await widget.bootstrap.ensureFirebaseInitialized(
      retryIfUnavailable: true,
    );
    if (!mounted) return;
    if (!firebaseReady) {
      setState(() {
        _isLoading = false;
        _error =
            'Cloud authentication is unavailable. Check your connection and try again.';
      });
      return;
    }

    final success = await AppState().login(email, _passCtrl.text);

    if (success && mounted) {
      setState(() => _isLoading = false);
    } else if (mounted) {
      // Check again — the failure may have just triggered a lockout
      if (limiter.isLockedOut(email)) {
        final secs = limiter.secondsRemaining(email);
        _startLockoutCountdown(secs);
        setState(() {
          _isLoading = false;
          _error = 'Too many failed attempts. Try again in ${secs}s.';
        });
      } else {
        final remaining =
            LoginRateLimiter.maxAttempts - limiter.failureCount(email);
        setState(() {
          _isLoading = false;
          _error =
              AppState().lastAuthMessage ??
              (remaining > 0
                  ? 'Invalid email or password ($remaining attempt${remaining == 1 ? '' : 's'} left)'
                  : 'Invalid email or password');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 700;

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
                    : Column(
                        children: [_buildBrandPanelMobile(), _buildFormPanel()],
                      ),
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
            const Text(
              AppStrings.appSubtitle,
              style: AppTextStyles.brandSubtitle,
            ),
            const SizedBox(height: 20),
            // UNLEASH • CONFIDENCE • ELEVATE tagline
            const Text(
              'UNLEASH  •  CONFIDENCE  •  ELEVATE',
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 11,
                letterSpacing: 2.0,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.4),
                ),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Text(
                '✦  ${AppStrings.luxuryFragranceHouse}  ✦',
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 13,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandPanelMobile() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
      decoration: const BoxDecoration(
        gradient: AppColors.sidebarGradient,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // KNZ actual logo image with pulsing rings
          _buildPulsingLogo(size: 120),
          const SizedBox(height: 20),
          Text(
            AppStrings.appName,
            style: AppTextStyles.brandName.copyWith(fontSize: 26),
          ),
          const SizedBox(height: 4),
          const Text(
            AppStrings.appSubtitle,
            style: AppTextStyles.brandSubtitle,
          ),
          const SizedBox(height: 14),
          // UNLEASH • CONFIDENCE • ELEVATE tagline
          const Text(
            'UNLEASH  •  CONFIDENCE  •  ELEVATE',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 11,
              letterSpacing: 2.0,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // Builds three concentric animated rings around the KNZ logo image.
  // Opacity pulses with the _pulse animation for a breathing effect.
  Widget _buildPulsingLogo({double size = 110}) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            _ring(
              size * 1.4,
              AppColors.gold.withValues(alpha: 0.05 * _pulse.value),
            ),
            _ring(
              size * 1.15,
              AppColors.gold.withValues(alpha: 0.1 * _pulse.value),
            ),
            _ring(size, AppColors.gold.withValues(alpha: 0.15 * _pulse.value)),
            // KNZ logo image inside the rings
            Container(
              width: size * 0.82,
              height: size * 0.82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.6),
                  width: 1.5,
                ),
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/icon/app_icon_fitted.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _ring(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.5),
      ),
    );
  }

  Widget _buildFormPanel() {
    final isWide = MediaQuery.of(context).size.width > 700;
    return Expanded(
      flex: isWide ? 1 : 0,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tab header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.gold, width: 2),
                ),
              ),
              child: const Text(
                'SIGN IN',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.gold,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 28),
            DarkTextField(
              label: 'EMAIL ADDRESS',
              hint: 'Enter your email address',
              controller: _userCtrl,
            ),
            const SizedBox(height: 16),
            DarkTextField(
              label: AppStrings.password,
              hint: '••••••••',
              controller: _passCtrl,
              obscureText: true,
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ],
            const SizedBox(height: 24),
            GoldButton(
              label: _lockoutSeconds > 0
                  ? 'Try again in ${_lockoutSeconds}s'
                  : _isLoading
                  ? '...'
                  : AppStrings.enterPortal,
              onPressed: (_isLoading || _lockoutSeconds > 0) ? () {} : _login,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.inputFill,
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              alignment: Alignment.center,
              child: const Text(
                AppStrings.defaultLogin,
                style: TextStyle(color: AppColors.whiteTertiary, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),

            // Forgot Password
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
              ),
              child: const Center(
                child: Text(
                  'Forgot Password?',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Divider
            Row(
              children: [
                Expanded(child: Divider(color: AppColors.cardBorder)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'OR',
                    style: TextStyle(
                      color: AppColors.whiteTertiary,
                      fontSize: 11,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: AppColors.cardBorder)),
              ],
            ),
            const SizedBox(height: 16),

            // Sign Up button
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RegisterScreen(bootstrap: widget.bootstrap),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.4),
                  ),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'CREATE NEW ACCOUNT',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
