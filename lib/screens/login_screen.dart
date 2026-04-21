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
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../widgets/shared_widgets.dart';
import 'main_shell.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isLoading = false;
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
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  // Calls AppState.login() with the entered credentials.
  // On success, navigates to MainShell with a fade transition.
  // On failure, shows an 'Invalid username or password' error.
  void _login() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final success =
        await AppState().login(_userCtrl.text.trim(), _passCtrl.text.trim());
    if (success && mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 600),
          pageBuilder: (_, anim, __) => FadeTransition(
            opacity: anim,
            child: const MainShell(),
          ),
        ),
      );
    } else if (mounted) {
      setState(() {
        _isLoading = false;
        _error = 'Invalid username or password';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 700;

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
                      _buildFormPanel()
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
            const Text(AppStrings.appSubtitle, style: AppTextStyles.brandSubtitle),
            const SizedBox(height: 32),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
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
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
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

  // Builds three concentric animated rings around the app logo icon.
  // Opacity pulses with the _pulse animation for a breathing effect.
  Widget _buildPulsingLogo({double size = 110}) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) {
        return Stack(
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
              child: Icon(
                Icons.water_drop_outlined,
                color: AppColors.gold,
                size: size * 0.3,
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
              label: AppStrings.username,
              hint: 'Enter your username',
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
              Text(_error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 13)),
            ],
            const SizedBox(height: 24),
            GoldButton(
              label: _isLoading ? '...' : AppStrings.enterPortal,
              onPressed: _isLoading ? () {} : _login,
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
                style: TextStyle(
                    color: AppColors.whiteTertiary, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),

            // Forgot Password
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ForgotPasswordScreen(),
                ),
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
            Row(children: [
              Expanded(child: Divider(color: AppColors.cardBorder)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('OR', style: TextStyle(color: AppColors.whiteTertiary, fontSize: 11)),
              ),
              Expanded(child: Divider(color: AppColors.cardBorder)),
            ]),
            const SizedBox(height: 16),

            // Sign Up button
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RegisterScreen(),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
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
