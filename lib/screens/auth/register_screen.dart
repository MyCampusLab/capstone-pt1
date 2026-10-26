// ==========================================
// file: lib/screens/auth/register_screen.dart
// deskripsi: layar registrasi untuk membuat akun baru
// penjelasan:
//   - user memasukkan nama, email, password & confirm password
//   - ada validasi form (email format, password strength, matching)
//   - ada tombol google sign-up (placeholder)
//   - setelah register sukses, navigasi ke login screen
//   - dibuat akun di firebase auth & user document di firestore
// ==========================================

import 'package:flutter/gestures.dart';
import 'package:geges_smartbarber/config/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:geges_smartbarber/l10n/generated/app_localizations.dart';
import 'package:geges_smartbarber/screens/auth/login_screen.dart';
import 'package:geges_smartbarber/services/auth_service.dart';

// penjelasan statefulwidget:
// - registerscreen adalah statefulwidget karena ada state yang berubah (error message, loading)
// - setstate() dipanggil untuk update ui saat ada perubahan
class RegisterScreen extends StatefulWidget {
  final AuthServiceBase? authService;
  const RegisterScreen({super.key, this.authService});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // penjelasan controller:
  // - textEditingController digunakan untuk menangkap text yang user ketik di TextField
  // - _nameController untuk menangkap input nama
  // - _emailController untuk menangkap input email
  // - _passwordController untuk menangkap input password
  // - _confirmPasswordController untuk menangkap konfirmasi password
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  // FocusNodes for inputs to allow animated focused styling
  late final FocusNode _nameFocusNode;
  late final FocusNode _emailFocusNode;
  late final FocusNode _passwordFocusNode;
  late final FocusNode _confirmFocusNode;

  // penjelasan authservice:
  // - authservice adalah service yang menangani semua operasi autentikasi
  // - digunakan untuk registerCustomer dan signInWithGoogle
  AuthServiceBase? _authService;

  // NOTE: removed direct Firebase instances to avoid initialization during widget tests
  // (we rely on AuthService for all firebase interactions)

  // penjelasan variabel state:
  // - _errorMessage: menampilkan pesan error jika registrasi gagal
  // - _isLoading: flag untuk menampilkan loading spinner saat proses registrasi
  // - _passwordVisible: flag untuk toggle password visibility
  String _errorMessage = '';
  bool _isLoading = false;
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;

  // penjelasan warna tema:
  // - kBrownAccent: warna coklat utama dari design system
  // - kDarkGrey: warna background untuk input field
  // - kHintText: warna teks hint/placeholder
  static const Color kBrownAccent = AppColors.primary;
  static const Color kDarkGrey = AppColors.surface;
  static const Color kHintText = AppColors.textMuted;

  // UI strings moved to AppStrings to prepare for localization. See lib/l10n/app_strings.dart
  // Note: full ARB/localization migration to follow as a separate task.

  @override
  void initState() {
    super.initState();
    // Defer to injected AuthService if provided (avoids initializing Firebase in widget tests)
    _authService = widget.authService;
    // initialize focus nodes for animated input styling
    _nameFocusNode = FocusNode();
    _emailFocusNode = FocusNode();
    _passwordFocusNode = FocusNode();
    _confirmFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    // dispose focus nodes
    _nameFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmFocusNode.dispose();
    super.dispose();
  }

  // ========================================
  // fungsi registrasi dengan firebase auth & firestore
  // ========================================
  Future<void> _register() async {
    // penjelasan:
    // - fungsi ini dijalankan saat user tekan tombol "create account"
    // - mengambil nilai nama, email, password & confirm password dari controller
    // - validasi form (jangan kosong, password match, password min 6 char)
    // - buat akun firebase auth dengan email & password
    // - update display name di auth
    // - buat user document di firestore
    // - kirim email verifikasi
    // - jika sukses, navigasi ke login screen
    // - jika gagal, tampilkan error message

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();

    final l10n = AppLocalizations.of(context)!;

    // penjelasan validasi input:
    // - cek apakah ada field yang kosong
    // - jika ada, tampilkan error message & return
    if (name.isEmpty || email.isEmpty || password.isEmpty || confirm.isEmpty) {
      setState(() => _errorMessage = l10n.registerErrAllFields);
      return;
    }

    // penjelasan validasi nama:
    // - minimal 3 karakter untuk nama valid
    if (name.length < 3) {
      setState(() => _errorMessage = l10n.registerErrNameMin);
      return;
    }

    // penjelasan validasi email:
    // - cek format email dengan regex
    final emailRegex = RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$');
    if (!emailRegex.hasMatch(email)) {
      setState(() => _errorMessage = l10n.registerErrEmailFormat);
      return;
    }

    // penjelasan validasi password match:
    // - cek apakah password dan konfirmasi sama
    // - jika tidak cocok, tampilkan error message
    if (password != confirm) {
      setState(() => _errorMessage = l10n.registerErrPasswordMismatch);
      return;
    }

    // penjelasan validasi password strength:
    // - cek apakah password minimal 6 karakter
    // - ini adalah minimal requirement dari firebase
    if (password.length < 6) {
      setState(() => _errorMessage = l10n.registerErrPasswordMin);
      return;
    }

    // penjelasan setstate loading:
    // - ubah state _isLoading = true untuk menampilkan spinner
    // - kosongkan _errorMessage untuk menghapus pesan error sebelumnya
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Gunakan AuthService untuk register (lebih clean dan reusable)
      final auth = _authService ?? AuthService();
      final result = await auth.registerCustomer(
        email: email,
        password: password,
        name: name,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        // Tampilkan snackbar sukses & navigasi ke login
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? l10n.registerMsgSuccess),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
        _goToLogin();
      } else {
        // Tampilkan error message
        setState(
          () => _errorMessage = result['message'] ?? l10n.errGeneric('Registrasi gagal.'),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = l10n.errGeneric(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ========================================
  // navigasi ke login screen
  // ========================================
  void _goToLogin() {
    // penjelasan:
    // - fungsi ini dipanggil saat user tekan tombol "log in" atau setelah register sukses
    // - navigasi ke loginscreen dengan pushReplacement (ganti screen, jangan push)
    // - transitionduration zero untuk instant transition tanpa animasi

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const LoginScreen(),
        transitionDuration: Duration.zero,
      ),
    );
  }

  // ========================================
  // google sign-up dengan real google authentication
  // ========================================
  void _signInWithGoogle() async {
    // penjelasan:
    // - fungsi ini dijalankan saat user tekan tombol "continue with google"
    // - panggil _authService.signInWithGoogle() untuk authenticate dengan google
    // - jika user belum terdaftar, akan otomatis dibuat account baru
    // - jika user sudah terdaftar, akan login langsung
    // - navigasi ke login screen untuk menunjukkan sukses

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
        // Sukses registrasi/login dengan Google
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.registerMsgGoogleSuccess),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
        // Langsung navigasi ke Login agar user bisa masuk dengan role yang tepat
        _goToLogin();
      } else {
        // Tampilkan error
        final message = result['message'] ?? l10n.errGeneric('Google sign-up gagal.');
        setState(() => _errorMessage = message);

        // Jika error related to recaptcha atau credential, tawarkan retry
        final isRecaptcha =
            message.toLowerCase().contains('recaptcha') ||
            message.toLowerCase().contains('captcha');
        final isCredential =
            message.toLowerCase().contains('credential') ||
            message.toLowerCase().contains('developer_error') ||
            message.toLowerCase().contains('oauth');

        if (isRecaptcha || isCredential) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: const Color(0xFFD32F2F),
              action: SnackBarAction(
                label: l10n.btnRetry,
                textColor: Colors.white,
                onPressed: _signInWithGoogle,
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = l10n.errGeneric(e.toString());
      });

      // Tawarkan retry untuk error tertentu
      final msg = e.toString().toLowerCase();
      if (msg.contains('recaptcha') ||
          msg.contains('credential') ||
          msg.contains('developer_error')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.errGeneric(e.toString())),
            backgroundColor: const Color(0xFFD32F2F),
            action: SnackBarAction(
              label: l10n.btnRetry,
              textColor: Colors.white,
              onPressed: _signInWithGoogle,
            ),
          ),
        );
      }
    }
  }

  // Helper function to check password strength
  String _getPasswordStrength(String password, AppLocalizations l10n) {
    if (password.length < 6) return l10n.strengthWeak;
    final hasUpper = password.contains(RegExp(r'[A-Z]'));
    final hasLower = password.contains(RegExp(r'[a-z]'));
    final hasDigit = password.contains(RegExp(r'[0-9]'));
    final hasSpecial = password.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'));
    int score = [
      hasUpper,
      hasLower,
      hasDigit,
      hasSpecial,
    ].where((b) => b).length;
    if (score <= 2) return l10n.strengthMedium;
    if (score >= 3) return l10n.strengthStrong;
    return l10n.strengthWeak;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // penjelasan build():
    // - method ini menampilkan ui layar register
    // - scaffold = layout dasar dengan appbar, body, dll
    // - singlechildscrollview = membuat content bisa di-scroll jika terlalu panjang
    // - column = tata letak vertikal (dari atas ke bawah)

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        // penjelasan safarea:
        // - safarea memastikan content tidak overlap dengan status bar atau notch
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // penjelasan logo:
              // - image.asset memuat gambar dari folder assets
              // - height 120 untuk mengatur ukuran logo
              // - errorbuilder menampilkan icon jika gambar tidak ditemukan
              Image.asset(
                'assets/images/ivon.png',
                height: 120,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.cut, color: kBrownAccent, size: 120),
              ),
              const SizedBox(height: 24),

              // penjelasan judul & subtitle:
              // - text untuk menampilkan teks statis
              // - textalign center untuk meratakan ke tengah
              // - fontsize & fontweight untuk mengatur ukuran & tebal
              Text(
                l10n.welcome,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              // subtitle
              Text(
                l10n.welcomeSubtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 32),

              // penjelasan tab login/signup:
              // - _buildAuthTabs() adalah custom widget untuk tombol tab login/signup
              // - isLogin false karena ini halaman signup
              // - onLoginTap callback dipanggil saat user tekan tab "log in"
              _buildAuthTabs(
                  isLogin: false,
                  onLoginTap: _goToLogin,
                  loginLabel: l10n.signInTab,
                  signUpLabel: l10n.signUp),
              const SizedBox(height: 32),

              // penjelasan input fields:
              // - 4 text fields untuk nama, email, password, confirm password
              // - _buildTextField() adalah custom widget untuk input field styling
              // - hinttext, icon, keyboardtype parameter untuk konfigurasi
              // username field
              _buildTextField(
                _nameController,
                l10n.username,
                Icons.person_outline,
                key: const Key('register_name'),
                focusNode: _nameFocusNode,
              ),
              const SizedBox(height: 16),
              // email field
              _buildTextField(
                _emailController,
                l10n.email,
                Icons.email_outlined,
                key: const Key('register_email'),
                keyboardType: TextInputType.emailAddress,
                focusNode: _emailFocusNode,
              ),
              const SizedBox(height: 16),
              // password field (hidden)
              _buildTextField(
                _passwordController,
                l10n.password,
                Icons.lock_outline,
                key: const Key('register_password'),
                isObscure: !_passwordVisible,
                onPasswordToggle: () =>
                    setState(() => _passwordVisible = !_passwordVisible),
                focusNode: _passwordFocusNode,
              ),
              const SizedBox(height: 16),
              // confirm password field (hidden)
              _buildTextField(
                _confirmPasswordController,
                l10n.confirmPassword,
                Icons.lock_outline,
                key: const Key('register_confirm_password'),
                isObscure: !_confirmPasswordVisible,
                onPasswordToggle: () => setState(
                  () => _confirmPasswordVisible = !_confirmPasswordVisible,
                ),
                focusNode: _confirmFocusNode,
              ),
              const SizedBox(height: 20),

              // penjelasan password strength indicator:
              // - ditampilkan di bawah password field
              // - menunjukkan kekuatan password: lemah/sedang/kuat
              // - warna hijau/orange/merah sesuai dengan tingkat kekuatan
              Padding(
                padding: const EdgeInsets.only(left: 8.0, top: 4.0),
                child: Text(
                  '${l10n.strengthLabel}${_getPasswordStrength(_passwordController.text, l10n)}',
                  style: TextStyle(
                    color:
                        _getPasswordStrength(_passwordController.text, l10n) == l10n.strengthStrong
                        ? Colors.green
                        : (_getPasswordStrength(_passwordController.text, l10n) ==
                                  l10n.strengthMedium
                              ? Colors.orange
                              : Colors.red),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),

              // penjelasan error message:
              // - hanya ditampilkan jika _errorMessage tidak kosong
              // - padding untuk spacing
              // - text style warna merah untuk error
              if (_errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    _errorMessage,
                    key: const Key('register_error_text'),
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

              // penjelasan create account button:
              // - sizedbox height 55 untuk mengatur tinggi tombol
              // - jika _isLoading true, tampilkan spinner
              // - jika false, tampilkan elevatedbutton dengan label "create account"
              // - onpressed memanggil _register()
              SizedBox(
                height: 55,
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: kBrownAccent),
                      )
                    : ElevatedButton(
                        key: const Key('register_create_btn'),
                        onPressed: _register,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kBrownAccent,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          l10n.createAccount,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 32),

              // penjelasan separator:
              // - baris dengan garis di kanan-kiri dengan "or" di tengah
              // - row dengan expanded untuk membuat garis responsive
              _buildSeparator(),
              const SizedBox(height: 32),

              // penjelasan google sign-up button:
              // - elevatedbutton.icon untuk tombol dengan icon & text
              // - image.asset memuat google logo
              // - onpressed memanggil _signInWithGoogle()
              SizedBox(
                height: 55,
                child: ElevatedButton.icon(
                  key: const Key('register_google_btn'),
                  onPressed: _signInWithGoogle,
                  icon: Image.asset(
                    'assets/images/google.png',
                    height: 24,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.android,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  label: Text(
                    l10n.continueWithGoogle,
                    style: const TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kDarkGrey,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade800),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // penjelasan footer terms:
              // - richtext untuk membuat text dengan style berbeda di bagian yang berbeda
              // - textspan untuk mendefinisikan style per bagian
              // - tapgesturerecognizer untuk membuat teks clickable
              _buildFooterTerms(l10n),
            ],
          ),
        ),
      ),
    );
  }

  // ========================================
  // custom widget: tab untuk login/signup
  // ========================================
  Widget _buildAuthTabs({
    required bool isLogin,
    required VoidCallback onLoginTap,
    required String loginLabel,
    required String signUpLabel,
  }) {
    // penjelasan:
    // - widget ini menampilkan 2 tab: "log in" dan "sign up"
    // - tab yang aktif memiliki background coklat
    // - tab yang tidak aktif transparan
    // - ontap callback dipanggil saat user tekan tab

    return Container(
      decoration: BoxDecoration(
        color: kDarkGrey,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // penjelasan tab login:
          // - gesturedetector untuk mendeteksi tap
          // - ontap callback untuk navigasi ke login screen
          // - container dengan background coklat jika aktif (islogin true)
          Expanded(
            child: GestureDetector(
              onTap: onLoginTap,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: isLogin ? kBrownAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  loginLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isLogin ? Colors.black : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
          // penjelasan tab signup:
          // - expanded membuat tab mengambil ruang sama rata
          // - container dengan background coklat untuk tab signup (aktif)
          // - text "sign up" dengan alignment center
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: !isLogin ? kBrownAccent : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                signUpLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========================================
  // custom widget: text input field
  // ========================================
  Widget _buildTextField(
    TextEditingController c,
    String hint,
    IconData icon, {
    Key? key,
    bool isObscure = false,
    TextInputType keyboardType = TextInputType.text,
    VoidCallback? onPasswordToggle,
    FocusNode? focusNode,
  }) {
    // penjelasan:
    // - reusable widget untuk membuat input field dengan style yang konsisten
    // - c: controller menangkap text yang user ketik
    // - hint: placeholder text saat field kosong
    // - icon: icon di sebelah kiri input
    // - isobscure: true untuk password field (hide character)
    // - keyboardtype: tipe keyboard yang muncul (email, number, text, dll)
    // - onpasswordtoggle: callback untuk toggle password visibility

    final node = focusNode;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: kDarkGrey,
        borderRadius: BorderRadius.circular(20),
        boxShadow: (node != null && node.hasFocus)
            ? [
                BoxShadow(
                  color: kBrownAccent.withValues(alpha: 0.12),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: TextField(
        key: key,
        controller: c,
        obscureText: isObscure,
        keyboardType: keyboardType,
        focusNode: node,
        onChanged: (_) =>
            setState(() {}), // Rebuild untuk password strength indicator
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: kHintText),
          filled: true,
          fillColor: Colors.transparent,
          prefixIcon: Icon(icon, color: kHintText, size: 22),
          suffixIcon: onPasswordToggle != null
              ? IconButton(
                  icon: Icon(
                    isObscure ? Icons.visibility : Icons.visibility_off,
                    color: kHintText,
                  ),
                  onPressed: onPasswordToggle,
                )
              : null,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: kBrownAccent, width: 1.5),
          ),
        ),
      ),
    );
  }

  // ========================================
  // custom widget: separator dengan "or" text
  // ========================================
  Widget _buildSeparator() {
    // penjelasan:
    // - widget ini menampilkan baris dengan garis di kanan-kiri dengan "or" di tengah
    // - divider untuk membuat garis horizontal
    // - row dengan expanded untuk membuat garis responsive

    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade800)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          child: Text('or', style: TextStyle(color: Colors.white70)),
        ),
        Expanded(child: Divider(color: Colors.grey.shade800)),
      ],
    );
  }

  // ========================================
  // custom widget: footer dengan terms & privacy policy
  // ========================================
  Widget _buildFooterTerms(AppLocalizations l10n) {
    // penjelasan footer terms:
    // - richtext untuk membuat text dengan style berbeda di bagian yang berbeda
    // - textspan untuk mendefinisikan style per bagian
    // - tapgesturerecognizer untuk membuat teks clickable

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: const TextStyle(color: Colors.white54, fontSize: 12),
        children: [
          TextSpan(text: l10n.termFooterPre),
          TextSpan(
            text: l10n.termFooterService,
            style: const TextStyle(
              color: kBrownAccent,
              decoration: TextDecoration.underline,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                Navigator.of(context).pushNamed('/legal/terms');
              },
          ),
          TextSpan(text: l10n.termFooterAnd),
          TextSpan(
            text: l10n.termFooterPrivacy,
            style: const TextStyle(
              color: kBrownAccent,
              decoration: TextDecoration.underline,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                Navigator.of(context).pushNamed('/legal/privacy');
              },
          ),
        ],
      ),
    );
  }
}
