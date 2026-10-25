import 'package:flutter/material.dart';
// import 'package:flutter/foundation.dart'; // Removed: Unnecessary
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geges_smartbarber/services/queue_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:geges_smartbarber/l10n/generated/app_localizations.dart';
import 'package:geges_smartbarber/utils/locale_provider.dart';
import 'firebase_options.dart';
import 'package:geges_smartbarber/services/notification_service.dart';
import 'package:geges_smartbarber/services/app_navigator.dart';
import 'package:geges_smartbarber/screens/admin/barber_shops_list_screen.dart';
import 'package:geges_smartbarber/screens/tenant/tenant_registration_screen.dart';
import 'package:geges_smartbarber/screens/legal/terms_page.dart';
import 'package:geges_smartbarber/screens/legal/privacy_page.dart';
import 'package:geges_smartbarber/screens/intro/splash_screen.dart';
import 'package:geges_smartbarber/services/network_service.dart';
import 'package:geges_smartbarber/services/system_optimization_service.dart';
import 'package:geges_smartbarber/widgets/offline_screen.dart';
import 'package:geges_smartbarber/widgets/enterprise_error_widget.dart';
import 'package:geges_smartbarber/config/app_config.dart'; // Import Config
import 'package:sentry_flutter/sentry_flutter.dart';

// ==========================================

const String sentryDsn = String.fromEnvironment(
  'SENTRY_DSN',
  defaultValue: 'https://6ae0b86bbd9b4371c7f7dbc599e5b419@o4510682370015232.ingest.us.sentry.io/4510682373554176',
);

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Custom Error Widget for Enterprise look
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return EnterpriseErrorWidget(details: details);
  };

  await initializeDateFormatting('id_ID', null);

  await SentryFlutter.init(
    (options) {
      options.dsn = sentryDsn;
      options.tracesSampleRate = 1.0; 
      options.profilesSampleRate = 1.0;
      options.attachScreenshot = true;
      options.environment = AppConfig.environment == Environment.prod ? 'production' : 'development';
    },
    appRunner: () async {
      try {
        await Sentry.addBreadcrumb(Breadcrumb(message: "Application Started"));
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        
        // Initialize App Check: Use Play Integrity for production
        try {
          await FirebaseAppCheck.instance.activate(
            androidProvider: AppConfig.environment == Environment.prod 
                ? AndroidProvider.playIntegrity 
                : AndroidProvider.debug,
            appleProvider: AppleProvider.deviceCheck,
          );
        } catch (e) {
          debugPrint("App Check initialization failed (non-fatal): $e");
          await Sentry.addBreadcrumb(Breadcrumb(
            message: "App Check initialization failed",
            level: SentryLevel.error,
            category: "auth.appcheck",
            data: {"error": e.toString()},
          ));
          // Do NOT crash the app if App Check fails
        }

        try {
          await NotificationService.instance.init();
        } catch (_) {}
        NetworkService().init();
        
        // Remove splash after all services are ready
        FlutterNativeSplash.remove();

        runApp(
          ChangeNotifierProvider(
            create: (context) => LocaleProvider(),
            child: const MyApp(),
          ),
        );
      } catch (e, stackTrace) {
        await Sentry.captureException(e, stackTrace: stackTrace);
        FlutterNativeSplash.remove();
        runApp(
          EnterpriseErrorWidget(
            details: FlutterErrorDetails(
              exception: e,
              stack: stackTrace,
              library: 'Main Initialization',
            ),
          ),
        );
      }
    },
  );
}


class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final QueueService _queueService = QueueService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Try an initial check shortly after startup
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkAndCancelExpiredForCurrentUser();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // NetworkService dispose handled by singleton pattern usually, or kept alive
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // On resume, run expiry checks for current user
      _checkAndCancelExpiredForCurrentUser();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      // Clear cache when app is backgrounded or killed to keep it "Smart" and fresh
      SystemOptimizationService.instance.clearAppCache();
    }
  }

  Future<void> _checkAndCancelExpiredForCurrentUser() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      await Future.wait([
        _queueService.cancelExpiredWaitingQueuesForCustomer(uid),
        _queueService.cancelExpiredAwaitingPaymentQueuesForCustomer(uid),
      ]);
    } catch (e) {
      debugPrint('Error running expiry checks: $e');
    }
  }

  // ========================================
  // warna tema aplikasi
  // ========================================
  static const Color kBrownAccent = Color(0xFFC3A47B); // warna coklat utama
  static const Color kBlackBackground = Colors.black; // warna latar aplikasi
  static const Color kDarkGrey = Color(
    0xFF1E1E1E,
  ); // warna abu-abu gelap untuk cards

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LocaleProvider>(context);

    // penjelasan materialapp:
    // - materialapp adalah root widget dari aplikasi
    // - ini setup material design theme, navigation, locale, dll
    // - title = nama aplikasi (muncul di app switcher / recent apps)
    // - debugShowCheckedModeBanner = true = tampilkan "debug" banner (garis merah)
    //   false = sembunyikan banner (production setting)
    // - theme = style untuk seluruh aplikasi
    // - home = starting screen yang ditampilkan pertama kali
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      navigatorObservers: [SentryNavigatorObserver()], // Added for screen tracking
      title: 'GEGES SmartBarber',
      debugShowCheckedModeBanner: false,
      
      // Localization configuration
      locale: provider.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,

      // Global Builder untuk Offline Handling
      builder: (context, child) {
        return StreamBuilder<NetworkStatus>(
          stream: NetworkService().stream,
          initialData: NetworkStatus.online,
          builder: (context, snapshot) {
            if (snapshot.data == NetworkStatus.offline) {
              return const OfflineScreen();
            }
            return child ?? const SizedBox.shrink();
          },
        );
      },

      // admin routes
      routes: {
        '/admin/barber-management': (_) => const BarberShopsListScreen(),
        '/tenant/register': (_) => const TenantRegistrationScreen(),
// '/admin/tenant-requests' route removed

        '/legal/terms': (_) => const TermsPage(),
        '/legal/privacy': (_) => const PrivacyPage(),
      },

      // =====================================================
      // ========== KONFIGURASI TEMA APLIKASI ===========
      // =====================================================
      // penjelasan themedata.dark():
      // - memberikan base theme dark mode
      // - copyWith() mengubah beberapa property dari base theme
      // - ini lebih efisien daripada membuat custom theme dari 0
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        // Native-like smooth transitions
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: ZoomPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),

        // penjelasan primarycolor:
        // - warna utama yang digunakan untuk button, highlight, icon tertentu
        // - warna ini akan "dominan" di aplikasi
        primaryColor: kBrownAccent,

        // penjelasan scaffoldBackgroundColor:
        // - warna default background untuk semua scaffold di aplikasi
        // - scaffold adalah layout dasar dengan appbar, body, bottombar, dll
        // - ini mencegah setiap screen perlu set background color manual
        scaffoldBackgroundColor: kBlackBackground,

        // ========== colorScheme ==========
        // penjelasan colorscheme:
        // - mendefinisikan palet warna lengkap yang digunakan di seluruh app
        // - material design menggunakan colorscheme untuk konsistensi warna
        // - setiap color ada kontrasnya (on-color) untuk teks/icon di atasnya
        // - ini memastikan aksesibilitas (text contrast ratio)
        colorScheme: const ColorScheme.dark(
          // primary = warna utama untuk button, highlight, focused state
          primary: kBrownAccent,
          // secondary = warna alternatif untuk accent (tidak banyak dipakai di app ini)
          secondary: kBrownAccent,
          // surface = warna latar untuk card, dialog, dropdown, sheet
          surface: kDarkGrey,
          // onprimary = warna text/icon di atas primary color (harus contrast)
          onPrimary: Colors.black,
          // onsurface = warna text/icon di atas surface (default text color)
          onSurface: Colors.white,
        ),

        // ========== elevatedButtonTheme ==========
        // penjelasan elevatedbutton:
        // - elevated button adalah tombol "terangkat" dengan background
        // - ini tombol paling umum digunakan di app
        // - semua elevated button akan menggunakan style dari sini
        // - individual button bisa override style ini dengan styleFrom()
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            // backgroundcolor = warna isi tombol
            backgroundColor: kBrownAccent,
            // foregroundcolor = warna text/icon di dalam tombol
            foregroundColor: Colors.black,
            // shape = bentuk tombol
            shape: RoundedRectangleBorder(
              // borderradius = kelengkungan sudut (12 pixel)
              borderRadius: BorderRadius.circular(12),
            ),
            // padding = jarak antara text dan tepi tombol (inner spacing)
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            // textstyle = style untuk text di dalam tombol
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        // ========== inputDecorationTheme ==========
        // penjelasan input decoration:
        // - theme untuk style textfield (input box) di seluruh aplikasi
        // - filled = background diisi dengan color (jangan transparent)
        // - fillcolor = warna background field
        // - border = garis tepi field (outline)
        // - focusedborder = garis tepi saat field fokus (user sedang ketik)
        inputDecorationTheme: InputDecorationTheme(
          // filled = true = background field diisi dengan warna
          filled: true,
          // fillcolor = warna background field
          fillColor: kDarkGrey,
          // hintstyle = style untuk placeholder text saat field kosong
          hintStyle: TextStyle(color: Colors.grey.shade600),
          // prefixiconcolor = warna icon di sebelah kiri input
          prefixIconColor: Colors.grey.shade600,
          // border = garis tepi saat field tidak fokus
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            // Use a transparent border with same width as focused border to avoid layout shift on focus
            borderSide: BorderSide(color: Colors.transparent, width: 1.5),
            gapPadding: 0,
          ),
          // enabledborder = garis tepi saat field aktif tapi tidak fokus
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(color: Colors.transparent, width: 1.5),
          ),
          // focusedborder = garis tepi saat user sedang ketik (fokus)
          // ini untuk highlighting field yang sedang diisi
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            // borderSide = garis dengan warna coklat & tebal 1.5
            borderSide: const BorderSide(color: kBrownAccent, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 16,
          ),
          floatingLabelBehavior: FloatingLabelBehavior.never,
        ),

        // ========== appBarTheme ==========
        // penjelasan appbartheme:
        // - theme untuk app bar (header di atas setiap halaman)
        // - backgroundcolor = warna latar app bar
        // - elevation = ketinggian bayangan (drop shadow)
        appBarTheme: const AppBarTheme(
          backgroundColor: kBlackBackground,
          // elevation 0 = tidak ada bayangan
          elevation: 0,
        ),
      ),
      // =====================================================
      // ========== AKHIR KONFIGURASI TEMA ===========
      // =====================================================

      // penjelasan home:
      // - halaman pertama yang ditampilkan saat aplikasi dibuka
      // - OnboardingScreen = layar pengenalan aplikasi untuk user baru
      // - jika user sudah pernah buka, bisa langsung ke LoginScreen
      // - (implementasi bisa menggunakan shared_preferences untuk check)
      home: const SplashScreen(), // Ganti AuthGate dengan SplashScreen
    );
  }
}
