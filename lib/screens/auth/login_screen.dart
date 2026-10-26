// lib/screens/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:geges_smartbarber/config/app_colors.dart';
import 'package:geges_smartbarber/l10n/generated/app_localizations.dart';
import 'package:geges_smartbarber/services/auth_service.dart';
import 'package:geges_smartbarber/screens/customer/home_screen.dart';
import 'package:geges_smartbarber/screens/admin/admin_dashboard.dart';
import 'package:geges_smartbarber/screens/auth/register_screen.dart';

class LoginScreen extends StatefulWidget {
  final AuthServiceBase? authService;
  final WidgetBuilder? homeBuilder;
  final WidgetBuilder? adminBuilder;

  const LoginScreen({
    super.key,
    this.authService,
    this.homeBuilder,
    this.adminBuilder,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  late final FocusNode _emailFocusNode;
  late final FocusNode _passwordFocusNode;

  AuthServiceBase? _authService;
  String _errorMessage = '';
  bool _isLoading = false;
  bool _obscurePassword = true;


  @override
  void initState() {
    super.initState();
    _authService = widget.authService;
    _emailFocusNode = FocusNode();
    _passwordFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  void _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final l10n = AppLocalizations.of(context)!;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = l10n.errLoginEmpty);
      return;
    }

    final emailRegex = RegExp(r"^[\w\.-]+@[\w\.-]+\.\w+");
    if (!emailRegex.hasMatch(email)) {
      setState(() => _errorMessage = l10n.errEmailFormat);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final auth = _authService ?? AuthService();
      final result = await auth.signIn(email: email, password: password);

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (result['success'] == true) {
        _navigateByRole(result['role']);
      } else {
        setState(() => _errorMessage = result['message'] ?? l10n.errLoginFailed);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = l10n.errGeneric(e.toString());
      });
    }
  }

  void _navigateByRole(String? role) {
    final l10n = AppLocalizations.of(context)!;
    Widget targetScreen;
    if (role == 'customer') {
      targetScreen = widget.homeBuilder?.call(context) ?? const HomeScreen();
    } else if (role == 'admin_owner' || role == 'owner' || role == 'admin' || role == 'super_admin') {
      targetScreen = widget.adminBuilder?.call(context) ?? const AdminDashboardScreen();
    } else {
      setState(() => _errorMessage = l10n.errRoleInvalid(role ?? '<null>'));
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => targetScreen),
    );
  }

  void _goToRegister() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, a1, a2) => const RegisterScreen(),
        transitionDuration: Duration.zero,
      ),
    );
  }

  void _forgotPassword() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      final inputEmail = await _askForEmailDialog();
      if (inputEmail != null && inputEmail.isNotEmpty) {
        _sendResetEmail(inputEmail);
      }
    } else {
      _sendResetEmail(email);
    }
  }

  Future<void> _sendResetEmail(String email) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final auth = _authService ?? AuthService();
      final res = await auth.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (res['success'] == true) {
        _showSnackbar(l10n.msgResetSent(email), AppColors.success);
      } else {
        _showSnackbar(res['message'] ?? l10n.msgResetFail, AppColors.danger);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackbar(l10n.errGeneric(e.toString()), AppColors.danger);
    }
  }

  void _signInWithGoogle() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final auth = _authService ?? AuthService();
      final result = await auth.signInWithGoogle();

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (result['success'] == true) {
        _navigateByRole(result['role']);
      } else {
        final message = result['message'] ?? 'Google sign-in gagal.';
        _showSnackbar(message, AppColors.danger);
        setState(() => _errorMessage = message);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = l10n.errGeneric(e.toString());
      });
      _showSnackbar(l10n.errGeneric(e.toString()), AppColors.danger);
    }
  }

  Future<String?> _askForEmailDialog() async {
    final l10n = AppLocalizations.of(context)!;
    String typed = '';
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(l10n.dialogResetTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: TextField(
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: l10n.dialogResetHint,
              hintStyle: const TextStyle(color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
            ),
            onChanged: (v) => typed = v,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text(l10n.btnCancel, style: const TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, typed.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black),
              child: Text(l10n.btnSend),
            ),
          ],
        );
      },
    );
  }

  void _showSnackbar(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                
                // Modern Hero Logo & Badge
                Center(
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2E2419), Color(0xFF1C1917)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.5), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.content_cut_rounded,
                      color: AppColors.primary,
                      size: 38,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Title & Subtitle
                Text(
                  l10n.welcome,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.welcomeSubtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 28),

                // Modern Pill Tab Selector
                _buildAuthPillTabs(
                  isLogin: true,
                  onSignUpTap: _goToRegister,
                  loginLabel: l10n.signInTab,
                  signUpLabel: l10n.signUp,
                ),
                const SizedBox(height: 24),

                // Email Input
                _buildModernTextField(
                  controller: _emailController,
                  hintText: l10n.email,
                  icon: Icons.alternate_email_rounded,
                  keyboardType: TextInputType.emailAddress,
                  focusNode: _emailFocusNode,
                ),
                const SizedBox(height: 14),

                // Password Input with Visibility Toggle
                _buildModernTextField(
                  controller: _passwordController,
                  hintText: l10n.password,
                  icon: Icons.lock_outline_rounded,
                  obscureText: _obscurePassword,
                  focusNode: _passwordFocusNode,
                  onPasswordToggle: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                const SizedBox(height: 8),

                // Forgot Password Link
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _forgotPassword,
                    child: Text(
                      l10n.forgotPassword,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Error Message Box
                if (_errorMessage.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16.0),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(color: Color(0xFFF87171), fontSize: 13, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // Primary Sign In Button
                SizedBox(
                  height: 52,
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: AppColors.primary),
                        )
                      : ElevatedButton(
                          onPressed: _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            l10n.login,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 24),

                // Separator
                Row(
                  children: [
                    const Expanded(child: Divider(color: AppColors.border, thickness: 1)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14.0),
                      child: Text(
                        'atau lanjutkan dengan',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ),
                    const Expanded(child: Divider(color: AppColors.border, thickness: 1)),
                  ],
                ),
                const SizedBox(height: 20),

                // Google Sign In Button (Modern Outlined)
                SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : _signInWithGoogle,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/images/google.png',
                          height: 20,
                          width: 20,
                          errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          l10n.continueWithGoogle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Multi-Role Hint Badge (Professional Footer)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
                    ),
                    child: Text(
                      'Portal: Pelanggan • Kapster • Kasir • Admin',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthPillTabs({
    required bool isLogin,
    required VoidCallback onSignUpTap,
    required String loginLabel,
    required String signUpLabel,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                loginLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          Expanded(
            child: Semantics(
              button: true,
              label: signUpLabel,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onSignUpTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    signUpLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    FocusNode? focusNode,
    bool obscureText = false,
    VoidCallback? onPasswordToggle,
  }) {
    final node = focusNode;
    final hasFocus = node?.hasFocus ?? false;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasFocus ? AppColors.primary : AppColors.border,
          width: hasFocus ? 1.5 : 1.0,
        ),
      ),
      child: TextField(
        controller: controller,
        focusNode: node,
        keyboardType: keyboardType,
        obscureText: obscureText,
        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
          prefixIcon: Icon(icon, color: hasFocus ? AppColors.primary : AppColors.textMuted, size: 20),
          suffixIcon: onPasswordToggle != null
              ? IconButton(
                  tooltip: obscureText ? 'Tampilkan kata sandi' : 'Sembunyikan kata sandi',
                  icon: Icon(
                    obscureText ? Icons.visibility : Icons.visibility_off,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                  onPressed: onPasswordToggle,
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: InputBorder.none,
        ),
      ),
    );
  }
}
