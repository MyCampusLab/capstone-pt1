// ==========================================
// file: lib/screens/intro/onboarding_screen.dart
// deskripsi: layar perkenalan aplikasi untuk user baru
// penjelasan:
//   - carousel dengan 3 halaman yang bisa di-swipe
//   - setiap halaman punya icon, judul, & subtitle
//   - ada dots indicator di bawah untuk menunjukkan halaman mana saat ini
//   - ada tombol skip untuk langsung ke login tanpa lihat semua halaman
//   - ada tombol next untuk pindah halaman, berubah jadi "get started" di halaman terakhir
// ==========================================

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geges_smartbarber/screens/auth/login_screen.dart';

// penjelasan statefulwidget:
// - onboardingscreen adalah statefulwidget karena ada state yang berubah (halaman saat ini)
// - setstate() dipanggil untuk update ui saat user swipe ke halaman lain
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  // penjelasan page controller:
  // - pagecontroller digunakan untuk mengontrol pageview (carousel)
  // - initialpage 0 berarti mulai dari halaman pertama (index 0)
  // - pagecontroller juga bisa detect page scroll & programmatically navigate
  final PageController _pageController = PageController(initialPage: 0);

  // penjelasan current page state:
  // - _currentPage menyimpan halaman mana yang sedang ditampilkan
  // - di-update saat user swipe atau tekan tombol next
  // - digunakan untuk menampilkan dots indicator & ubah label tombol
  int _currentPage = 0;

  // penjelasan onboarding data:
  // - list berisi 3 map dengan data untuk setiap halaman onboarding
  // - setiap map punya: image (path), title (judul), subtitle (deskripsi)
  // - image path adalah dari folder assets/images/
  // - data ini bisa dipindahkan ke constants file jika ada lebih banyak
  final List<Map<String, String>> _onboardingData = [
    {
      "image": "assets/images/onboarding_clock.png",
      "title": "Say Goodbye to Long Waits",
      "subtitle":
          "Book your spot in advance with GEGES and arrive just in time for your haircut.",
    },
    {
      "image": "assets/images/onboarding_pin.png",
      "title": "Find Nearby Barbers",
      "subtitle":
          "Discover the best barbershops in your area with ratings and reviews from real customers.",
    },
    {
      "image": "assets/images/onboarding_bot.png",
      "title": "Transparent Queue",
      "subtitle":
          "Monitor real-time queue status, fair barber assignment, and estimated service duration.",
    },
  ];

  // penjelasan warna tema:
  // - kBrownAccent adalah warna coklat utama dari design system
  // - digunakan untuk tombol, highlight, & indicator dots yang aktif
  static const Color kBrownAccent = Color(0xFFC3A47B);

  // ========================================
  // navigasi ke login screen
  // ========================================
  void _navigateToLogin() async {
    // penjelasan:
    // - fungsi ini dipanggil saat user tekan skip atau get started di halaman terakhir
    // - set preference 'seen_onboarding' = true agar tidak muncul lagi saat logout
    // - navigasi ke loginscreen dengan pushreplacement

    if (!mounted) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_onboarding', true);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // penjelasan build():
    // - method ini menampilkan ui layar onboarding
    // - scaffold = layout dasar dengan body
    // - stack = tata letak untuk menempatkan widget di atas widget lain
    // - positioned = menempatkan widget di posisi absolut (top, left, right, bottom)

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        // penjelasan safarea:
        // - safarea memastikan content tidak overlap dengan status bar atau notch
        child: Stack(
          children: [
            // penjelasan pageview:
            // - carousel widget untuk swipe antara halaman
            // - pagebuilder membuat item carousel berdasarkan index
            // - itemcount = jumlah halaman (3)
            // - onpagechanged callback saat user swipe ke halaman lain
            // - controller = pagecontroller untuk kontrol programmatic
            // 1. carousel halaman
            PageView.builder(
              controller: _pageController,
              itemCount: _onboardingData.length,
              onPageChanged: (int page) {
                // penjelasan onpagechanged:
                // - callback ini dipanggil saat user swipe atau programmatic navigate
                // - page = index halaman baru
                // - setstate untuk update ui (dots indicator & tombol label)
                setState(() {
                  _currentPage = page;
                });
              },
              itemBuilder: (context, index) {
                // penjelasan itembuilder:
                // - membuat widget untuk setiap halaman
                // - _buildpagecontent() custom widget untuk menampilkan konten halaman
                // - data dari _onboardingdata[index]
                return _buildPageContent(_onboardingData[index]);
              },
            ),

            // penjelasan positioned skip button:
            // - positioned = menempatkan widget di posisi absolut (top, right, dll)
            // - top 10, right 24 = di atas kanan layar
            // - textbutton = tombol tanpa background
            // 2. tombol skip di atas kanan
            Positioned(
              top: 10.0,
              right: 24.0,
              child: TextButton(
                onPressed: _navigateToLogin,
                child: const Text(
                  'Skip',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ),

            // penjelasan positioned kontrol navigasi:
            // - positioned = menempatkan di atas kanan layar
            // - bottom 40, left 24, right 24 = di bawah, full width
            // - column untuk vertical layout (dots + tombol)
            // 3. kontrol navigasi (dots & tombol next/get started)
            Positioned(
              bottom: 40.0,
              left: 24.0,
              right: 24.0,
              child: Column(
                children: [
                  // penjelasan dots indicator:
                  // - row untuk horizontal layout
                  // - mainaxisalignment center = dots di tengah
                  // - _buildpageindicator() membuat list of dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _buildPageIndicator(),
                  ),
                  const SizedBox(height: 40.0),

                  // penjelasan next/get started button:
                  // - sizedbox width double.infinity = full width
                  // - elevated button untuk tombol dengan latar
                  // - onpressed logic: jika halaman terakhir, ke login. jika tidak, next page
                  // - backgroundColor = kBrownAccent
                  // - padding vertical 16 untuk tinggi tombol
                  // - borderradius 12 untuk sudut melengkung
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        // penjelasan logic:
                        // - cek apakah halaman saat ini adalah halaman terakhir
                        // - jika ya, navigasi ke login
                        // - jika tidak, swipe ke halaman berikutnya
                        if (_currentPage == _onboardingData.length - 1) {
                          _navigateToLogin();
                        } else {
                          // penjelasan nextpage:
                          // - pagecontroller.nextpage() untuk swipe ke halaman berikutnya
                          // - duration 400ms = lama animasi swipe
                          // - curve easeInOut = easing animation (smooth)
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOut,
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kBrownAccent,
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                      ),
                      child: Text(
                        // penjelasan conditional button label:
                        // - jika di halaman terakhir, label "get started"
                        // - jika tidak, label "next"
                        _currentPage == _onboardingData.length - 1
                            ? 'Get Started'
                            : 'Next',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========================================
  // custom widget: konten halaman carousel
  // ========================================
  Widget _buildPageContent(Map<String, String> data) {
    // penjelasan:
    // - widget ini menampilkan konten 1 halaman carousel
    // - padding untuk jarak dari tepi layar
    // - column = vertical layout
    // - mainalignment center = konten di tengah layar
    // - crossalignment center = konten di tengah horizontal

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // penjelasan icon circle:
          // - container = lingkaran background
          // - width 180, height 180 = ukuran lingkaran
          // - shape circle = bentuk lingkaran
          // - image.asset = tampilkan image di dalam lingkaran
          // lingkaran ikon
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              color: Colors.grey.shade900.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(40.0),
              child: Image.asset(
                data['image']!,
                color: kBrownAccent,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.image_not_supported,
                  color: kBrownAccent,
                  size: 80,
                ),
              ),
            ),
          ),
          const SizedBox(height: 60.0),

          // penjelasan judul:
          // - text untuk menampilkan judul halaman
          // - textalign center = judul di tengah
          // - fontsize 26, fontweight bold = ukuran & tebal
          // - color white = warna putih
          Text(
            data['title']!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16.0),

          // penjelasan subtitle:
          // - text untuk menampilkan deskripsi halaman
          // - textalign center = subtitle di tengah
          // - fontsize 16, height 1.5 = ukuran & jarak antar baris
          // - color white70 = warna putih agak transparan
          Text(
            data['subtitle']!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ========================================
  // custom widget: dots indicator
  // ========================================
  List<Widget> _buildPageIndicator() {
    // penjelasan:
    // - membuat list of dots berdasarkan jumlah halaman
    // - setiap halaman punya 1 dot
    // - dot yang aktif (_currentpage) lebih panjang & warna coklat
    // - dot yang tidak aktif lebih pendek & warna abu-abu

    List<Widget> list = [];
    for (int i = 0; i < _onboardingData.length; i++) {
      // penjelasan logic:
      // - jika i == _currentpage, tampilkan dot aktif (isactive true)
      // - jika tidak, tampilkan dot tidak aktif (isactive false)
      list.add(i == _currentPage ? _indicator(true) : _indicator(false));
    }
    return list;
  }

  // ========================================
  // custom widget: 1 dot (aktif atau tidak)
  // ========================================
  Widget _indicator(bool isActive) {
    // penjelasan:
    // - widget untuk menampilkan 1 dot
    // - isactive true = dot aktif (panjang, coklat)
    // - isactive false = dot tidak aktif (pendek, abu-abu)
    // - animatedcontainer = container yang bisa di-animate
    // - duration 150ms = lama animasi transisi

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.symmetric(horizontal: 6.0),
      height: 8.0,
      // penjelasan width conditional:
      // - jika isactive true, width 24 (panjang)
      // - jika false, width 8 (pendek/lingkaran)
      // - transisi smooth 150ms dari satu width ke width lain
      width: isActive ? 24.0 : 8.0,
      decoration: BoxDecoration(
        // penjelasan color:
        // - jika isactive, color kBrownAccent (coklat)
        // - jika tidak, color grey.shade700 (abu-abu gelap)
        color: isActive ? kBrownAccent : Colors.grey.shade700,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}
