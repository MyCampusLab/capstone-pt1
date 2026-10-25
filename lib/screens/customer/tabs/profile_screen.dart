import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geges_smartbarber/l10n/generated/app_localizations.dart';
import 'package:geges_smartbarber/utils/locale_provider.dart';
import 'package:geges_smartbarber/services/auth_service.dart';
import 'package:geges_smartbarber/models/user_data.dart';
import 'package:geges_smartbarber/widgets/app_image.dart';
import 'package:geges_smartbarber/screens/auth/login_screen.dart';
import 'package:geges_smartbarber/screens/customer/tabs/favorite_barbershops_screen.dart';
import 'package:geges_smartbarber/screens/customer/app_rating_screen.dart';
import 'package:geges_smartbarber/screens/customer/tabs/my_bookings_screen.dart';
import 'package:geges_smartbarber/screens/tenant/tenant_registration_screen.dart';
import 'package:geges_smartbarber/screens/customer/edit_profile_screen.dart';
import 'package:geges_smartbarber/screens/common/change_password_screen.dart'; // Import ChangePasswordScreen

class ProfileScreen extends StatefulWidget {
  final AuthService? authService;
  const ProfileScreen({super.key, this.authService});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Theme colors
  static const Color kBrownAccent = Color(0xFFB9976E); 
  static const Color kSurface = Color(0xFF1B1B1B); 
  static const Color kCardColor = Color(0xFF2C2C2C); 
  static const Color kRedDanger = Color(0xFFDC3545); 
  static const Color kTextGrey = Color(0xFFB0B0B0); 
  static const Color kTextBlack = Color(0xFF1B1B1B); 

  late final AuthService _authService;
  late UserData _currentUser;
  late String _userEmail; 

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
    _currentUser = UserData(
      uid: _authService.currentUser?.uid ?? 'guest_uid',
      name: "Loading...", 
      role: "customer",
    );
    _userEmail = _authService.currentUser?.email ?? "...";
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final user = _authService.currentUser;
    if (user != null) {
      final userData = await _authService.getUserById(user.uid);
      if (mounted && userData != null) {
        setState(() {
          _currentUser = userData;
          _userEmail = user.email ?? "";
        });
      }
    }
  }

  void _logout() async {
    await _authService.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }

  void _goToEditProfile() async {
    final updatedUser = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditProfileScreen(currentUser: _currentUser),
      ),
    );

    if (updatedUser != null && updatedUser is UserData) {
      setState(() {
        _currentUser = updatedUser;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final localeProvider = Provider.of<LocaleProvider>(context);

    String displayName = _currentUser.name;
    if (displayName == "Loading...") displayName = l10n.loading;

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        title: Text(
          l10n.profileTab,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: kSurface,
        elevation: 0,
        automaticallyImplyLeading: false,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: _loadUserProfile,
        color: kBrownAccent,
        backgroundColor: kCardColor,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildProfileHeader(displayName),
              const SizedBox(height: 20),

              // --- MENU UTAMA ---
              _buildMenuCard(
                title: l10n.history,
                icon: Icons.history,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MyBookingsScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              // --- MENU BAHASA ---
              _buildMenuCard(
                title: l10n.language,
                icon: Icons.language,
                onTap: () => _showLanguageDialog(context, localeProvider),
              ),
              const SizedBox(height: 12),
              
              _buildMenuCard(
                title: l10n.favoriteBarbers,
                icon: Icons.favorite_border,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const FavoriteBarbershopsScreen(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 12),

              // --- MENU GANTI PASSWORD ---
              _buildMenuCard(
                title: l10n.changePassword, 
                icon: Icons.lock_outline,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ChangePasswordScreen(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 12),

              // --- MENU RATING ---
              _buildMenuCard(
                title: l10n.appRating,
                icon: Icons.star_outline,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AppRatingScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildMenuCard(
                title: l10n.termsOfService,
                icon: Icons.description_outlined,
                onTap: () {
                  Navigator.of(context).pushNamed('/legal/terms');
                },
              ),

              const SizedBox(height: 20),

              // --- TOMBOL LOGOUT ---
              ElevatedButton(
                onPressed: _logout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kRedDanger,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  l10n.signOut,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: 20),

              // --- PROMO CARD ---
              _buildBarbershopPromoCard(),
            ],
          ),
        ),
      ),
    );
  }

  void _showLanguageDialog(BuildContext context, LocaleProvider provider) {
    showDialog(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return AlertDialog(
          backgroundColor: kCardColor,
          title: Text(l10n.changeLanguage, style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Bahasa Indonesia', style: TextStyle(color: Colors.white)),
                leading: Radio<Locale>(
                  value: const Locale('id'),
                  // ignore: deprecated_member_use
                  groupValue: provider.locale,
                  // ignore: deprecated_member_use
                  onChanged: (Locale? v) {
                    if (v != null) provider.setLocale(v);
                    Navigator.pop(context);
                  },
                  activeColor: kBrownAccent,
                ),
                onTap: () {
                  provider.setLocale(const Locale('id'));
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('English', style: TextStyle(color: Colors.white)),
                leading: Radio<Locale>(
                  value: const Locale('en'),
                  // ignore: deprecated_member_use
                  groupValue: provider.locale,
                  // ignore: deprecated_member_use
                  onChanged: (Locale? v) {
                    if (v != null) provider.setLocale(v);
                    Navigator.pop(context);
                  },
                  activeColor: kBrownAccent,
                ),
                onTap: () {
                  provider.setLocale(const Locale('en'));
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProfileHeader(String displayName) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCardColor,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: kBrownAccent.withValues(alpha: 0.2),
            child: _currentUser.photoBase64 != null
                ? AppImage(
                    base64: _currentUser.photoBase64,
                    borderRadius: BorderRadius.circular(30),
                    fit: BoxFit.cover,
                  )
                : const Icon(Icons.person, size: 30, color: kBrownAccent),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _userEmail,
                  style: const TextStyle(color: kTextGrey, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Pengaturan Profil',
            onPressed: _goToEditProfile,
            icon: const Icon(Icons.settings, color: kTextGrey, size: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuCard({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: kCardColor,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Icon(icon, color: kTextGrey, size: 24),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: kTextGrey, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildBarbershopPromoCard() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.promoGrowTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.promoGrowSubtitle,
            style: const TextStyle(color: kTextGrey, fontSize: 14),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const TenantRegistrationScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kBrownAccent,
                foregroundColor: kTextBlack,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                l10n.registerMyBarbershop,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}