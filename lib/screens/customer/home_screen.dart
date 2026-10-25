// lib/screens/customer/home_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geges_smartbarber/l10n/generated/app_localizations.dart';
import 'package:geges_smartbarber/models/barbershop.dart';
import 'package:geges_smartbarber/models/promo_banner.dart';
import 'package:geges_smartbarber/services/barbershop_service.dart';
import 'package:geges_smartbarber/services/location_service.dart';
import 'package:geges_smartbarber/services/queue_service.dart';
import 'package:geges_smartbarber/services/auth_service.dart';
import 'package:geges_smartbarber/widgets/app_image.dart';
import 'package:geges_smartbarber/screens/customer/tabs/barbershop_detail_screen.dart';
import 'package:geges_smartbarber/screens/customer/tabs/profile_screen.dart';
import 'package:geges_smartbarber/screens/customer/tabs/my_bookings_screen.dart';
import 'package:geges_smartbarber/services/http_queue_repository.dart';
import 'package:geges_smartbarber/screens/customer/notifications_screen.dart';
import 'package:geges_smartbarber/widgets/skeleton_card.dart';
import 'package:geolocator/geolocator.dart';

class HomeScreen extends StatefulWidget {
  final BarbershopService? barbershopService;
  final LocationService? locationService;
  final QueueService? queueService;
  final AuthService? authService;
  final String? currentUserId; // For testing injection
  final int initialIndex;

  const HomeScreen({
    super.key, 
    this.barbershopService, 
    this.locationService, 
    this.queueService,
    this.authService,
    this.currentUserId,
    this.initialIndex = 0,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final BarbershopService _barbershopService;
  late final LocationService _locationService;
  late final QueueService _queueService;
  late final PageController _pageController;
  final TextEditingController _searchController = TextEditingController();
  static const Color kBrownAccent = Color(0xFFC3A47B);
  static const Color kDarkGrey = Color(0xFF1E1E1E);
  int _selectedIndex = 0;
  late Future<List<Barbershop>> _barbershopFuture;
  late Stream<List<Barbershop>> _barbershopStream;
  String _currentAddress = 'Menentukan lokasi...';
  bool _isLocating = false;
  List<Barbershop>? _searchResults;
  Timer? _debounce;
  Map<String, String> _serviceNames = {};
  Position? _userPosition;
  final Map<String, String> _shopDistances = {};

  @override void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(0, 2);
    _pageController = PageController(initialPage: _selectedIndex);
    _barbershopService = widget.barbershopService ?? BarbershopService();
    _locationService = widget.locationService ?? LocationService();
    _queueService = widget.queueService ?? QueueService();
    _barbershopFuture = _barbershopService.getAllBarbershops().then((shops) {
      if (_userPosition != null) _calculateAllDistances(shops);
      return shops;
    });
    _barbershopStream = _barbershopService.streamAllBarbershops();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateLocation();
        _fetchServiceNames();
      }
    });
  }

  Future<void> _fetchServiceNames() async {
    try {
      final services = await _barbershopService.getAllServices();
      if (mounted) setState(() => _serviceNames = {for (var s in services) s.id: s.name});
    } catch (e) { debugPrint("Error: $e"); }
  }

  Future<void> _updateLocation() async {
    if (_isLocating) return;
    setState(() { _isLocating = true; _currentAddress = 'Menentukan lokasi...'; });
    try {
      final pos = await _locationService.getCurrentPosition();
      final address = await _locationService.getCurrentLocationAddress();
      
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      
      if (mounted) {
        setState(() { 
          _userPosition = pos;
          _currentAddress = address ?? l10n.locationNotFound; 
          _isLocating = false; 
        });
        
        // Recalculate for loaded shops
        _barbershopFuture.then((shops) => _calculateAllDistances(shops));
      }
    } catch (e) { 
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() { _currentAddress = l10n.locationError; _isLocating = false; }); 
      }
    }
  }

  Future<void> _calculateAllDistances(List<Barbershop> shops) async {
    if (_userPosition == null) return;
    
    Map<String, String> newDistances = {};
    bool changed = false;

    for (var shop in shops) {
      if (_shopDistances.containsKey(shop.id)) continue; 
      final d = await _locationService.calculateDistanceToShop(_userPosition!, shop.addres);
      if (d != null) {
        newDistances[shop.id] = d;
        changed = true;
      }
    }
    
    if (changed && mounted) {
      setState(() {
        _shopDistances.addAll(newDistances);
      });
    }
  }

  @override void dispose() { _pageController.dispose(); _searchController.dispose(); _debounce?.cancel(); super.dispose(); }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
    }
    if (query.isEmpty) {
      setState(() => _searchResults = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 100), () async {
      try {
        final results = await _barbershopService.searchBarbershops(query);
        if (mounted) {
          setState(() => _searchResults = results);
          if (_userPosition != null) {
            _calculateAllDistances(results);
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _searchResults = []);
        }
      }
    });
  }

  void _onItemTapped(int index) { setState(() => _selectedIndex = index); _pageController.jumpToPage(index); }

  Widget _buildHeader() {
    final uid = widget.currentUserId ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    final l10n = AppLocalizations.of(context)!;
    final addressText = _isLocating ? l10n.locating : _currentAddress;

    return Padding(padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      GestureDetector(onTap: _isLocating ? null : _updateLocation, child: Row(children: [const Icon(Icons.location_on, color: Colors.white, size: 20), const SizedBox(width: 8), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Text(l10n.myLocation, style: const TextStyle(color: Colors.white70, fontSize: 12)), if (_isLocating) ...[const SizedBox(width: 8), const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2, color: kBrownAccent))] else ...[const SizedBox(width: 4), const Icon(Icons.refresh, color: Colors.white54, size: 12)]]), Text(addressText, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold))])])),
      StreamBuilder<int>(
        stream: _queueService.streamUnreadNotificationCount(uid),
        initialData: 0,
        builder: (context, snapshot) {
          final count = snapshot.data ?? 0;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(icon: const Icon(Icons.notifications_none_outlined, color: Colors.white, size: 28), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationsScreen())), tooltip: l10n.notifications),
              if (count > 0)
                Positioned(
                  top: 5,
                  right: 5,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Center(
                      child: Text(
                        count > 9 ? '9+' : count.toString(),
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
            ],
          );
        }
      ),
    ]));
  }

  Widget _buildSearchBar() {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: l10n.searchHintHome,
          hintStyle: const TextStyle(color: Color(0xFF9E9E9E)),
          prefixIcon: const Icon(Icons.search, color: Color(0xFF9E9E9E)),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _searchController,
            builder: (context, value, _) => value.text.isNotEmpty
                ? IconButton(
                    tooltip: 'Hapus teks pencarian',
                    icon: const Icon(Icons.clear, color: Color(0xFF9E9E9E), size: 20),
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                  )
                : const SizedBox.shrink(),
          ),
          filled: true,
          fillColor: kDarkGrey,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15.0), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15.0), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15.0),
            borderSide: const BorderSide(color: kBrownAccent, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildRecommendedList() {
    final l10n = AppLocalizations.of(context)!;
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 24.0), child: StreamBuilder<List<Barbershop>>(stream: _barbershopStream, builder: (context, snapshot) { 
      if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
        // IMPROVEMENT: Gunakan Skeleton Loader
        return Column(
          children: const [
            SkeletonBarbershopCard(),
            SkeletonBarbershopCard(),
          ],
        );
      } 
      if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) return Container(padding: const EdgeInsets.symmetric(vertical: 40), child: Center(child: Text(l10n.failedToLoadShops, style: const TextStyle(color: Colors.white70)))); 
      
      final shops = snapshot.data!;
      // Trigger distance calculation for newly streamed shops if user pos exists
      if (_userPosition != null) _calculateAllDistances(shops);

      return Column(children: shops.map((shop) => _buildBarbershopCard(context, shop)).toList());
    }));
  }

  Widget _buildBarbershopCard(BuildContext context, Barbershop shop) {
    // FILTER LOGIC: Hanya tampilkan service yang ada di map _serviceNames (valid)
    final validServices = shop.services.where((id) => _serviceNames.containsKey(id)).toList();
    final distance = _shopDistances[shop.id];
    final l10n = AppLocalizations.of(context)!;

    return GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => BarbershopDetailScreen(barbershop: shop))), child: Container(margin: const EdgeInsets.only(bottom: 20.0), decoration: BoxDecoration(color: kDarkGrey, borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Hero(
        tag: 'shop_image_${shop.id}',
        child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(20)), child: SizedBox(height: 180, width: double.infinity, child: _buildImage(shop.imageUrl))),
      ),
      Padding(padding: const EdgeInsets.all(20.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                  child: Text(shop.name,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)),
                              if (distance != null)
                                _DistanceBadge(distance: distance),
                            ]),
                        const SizedBox(height: 8),
                        Text(shop.addres,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 16),
                        // RENDER TAGS
                        Wrap(
                          spacing: 8.0,
                          runSpacing: 8.0,
                          children: validServices
                              .map((id) => _buildTagChip(id))
                              .toList(),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: shop.isOpen
                              ? ElevatedButton(
                                  onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (context) =>
                                              BarbershopDetailScreen(
                                                  barbershop: shop))),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: kBrownAccent,
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12))),
                                  child: Text(l10n.bookNow,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)))
                              : ElevatedButton(
                                  onPressed: null,
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: kRedDanger,
                                      disabledBackgroundColor: kRedDanger,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12))),
                                  child: Text(l10n.shopClosed, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))
                        )
                      ]))
            ])));
  }

  // Define kRedDanger if not present or use standard Colors.red
  static const Color kRedDanger = Color(0xFFDC3545);

  Widget _buildImage(String path) {
    return AppImage(
      imageUrl: path,
      fit: BoxFit.cover,
      errorWidget: Container(
        color: kDarkGrey,
        child: const Icon(Icons.broken_image, color: Colors.white54, size: 48),
      ),
    );
  }

  Widget _buildTagChip(String id) {
    // Karena kita sudah filter di atas, id pasti ada di map.
    final String label = _serviceNames[id] ?? id;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        decoration: BoxDecoration(
            color: Colors.grey.shade800,
            borderRadius: BorderRadius.circular(30.0)),
        child: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 12)));
  }

  Future<void> _handleRefresh() async {
    // Triggers all data re-fetching
    await Future.wait([
      _updateLocation(),
      _fetchServiceNames(),
      Future.delayed(const Duration(milliseconds: 500)), // Smooth transition
    ]);
    
    if (mounted) {
      setState(() {
        // Refresh the stream/future by re-assigning them
        _barbershopStream = _barbershopService.streamAllBarbershops();
        _barbershopFuture = _barbershopService.getAllBarbershops().then((shops) {
          if (_userPosition != null) _calculateAllDistances(shops);
          return shops;
        });
      });
    }
  }

  Widget _buildHomePageBody() {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _handleRefresh,
          color: kBrownAccent,
          backgroundColor: kDarkGrey,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(), // Essential for pull-to-refresh
            padding: EdgeInsets.zero, 
            children: [
              _buildHeader(),
              const SizedBox(height: 5),
              _buildSearchBar(),
              const SizedBox(height: 10),
              _buildActiveTicketBanner(),
              const SizedBox(height: 14),
              ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchController,
                  builder: (context, value, _) => value.text.isEmpty
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              PromoCarousel(barbershopService: _barbershopService),
                              const SizedBox(height: 21),
                              _buildTitle(l10n.barbershopsNearYou),
                              const SizedBox(height: 18),
                              _buildRecommendedList()
                            ])
                      : _buildSearch(value.text)),
              const SizedBox(height: 30),
            ]
          ),
        ));
  }
  Widget _buildActiveTicketBanner() {
    return FutureBuilder<Map<String, dynamic>?>(
      future: HttpQueueRepository().getActiveTicketLocally(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const SizedBox.shrink();
        }
        final ticket = snapshot.data!;
        final ticketNumber = ticket['ticketNumber']?.toString() ?? 'S-01';
        final shopName = ticket['tenantSlug']?.toString().replaceAll('-', ' ').toUpperCase() ?? 'BARBERSHOP';
        final estMins = ticket['estimatedDurationMinutes']?.toString() ?? '20';
        final barberName = (ticket['assignedBarber'] is Map)
            ? ticket['assignedBarber']['name']?.toString() ?? 'Kapster'
            : 'Kapster';

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 6.0),
          child: Semantics(
            button: true,
            label: 'Tiket antrean aktif $ticketNumber di $shopName, kapster $barberName, estimasi $estMins menit',
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _onItemTapped(1),
              child: Container(
            padding: const EdgeInsets.all(14.0),
            decoration: BoxDecoration(
              color: const Color(0xFF241E17),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kBrownAccent.withValues(alpha: 0.5), width: 1.5),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: kBrownAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      const Text('TIKET', style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold)),
                      Text(ticketNumber, style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shopName, style: const TextStyle(color: kBrownAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      const SizedBox(height: 2),
                      Text('Kapster: $barberName', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('Estimasi: ~$estMins menit', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios, color: kBrownAccent, size: 16),
                  onPressed: () => _onItemTapped(1),
                  tooltip: 'Lihat Antrean',
                ),
              ],
            ),
          ),
        ),
      ),
    );
      },
    );
  }

  Widget _buildSearch(String q) {
    final l10n = AppLocalizations.of(context)!;
    if (_searchResults == null) {
      return const Padding(padding: EdgeInsets.only(top: 40.0), child: Center(child: CircularProgressIndicator(color: kBrownAccent)));
    }
    if (_searchResults!.isEmpty) {
      return Padding(padding: const EdgeInsets.only(top: 40.0), child: Center(child: Column(children: [const Icon(Icons.search_off, size: 64, color: Colors.white38), const SizedBox(height: 16), Text(l10n.noResultsFor(q), style: const TextStyle(color: Colors.white70, fontSize: 16))])));
    }
    final count = _searchResults!.length;
    final resultText = l10n.foundResults(count);
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(resultText,
              style: const TextStyle(
                  color: kBrownAccent, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ..._searchResults!.map((shop) => _buildBarbershopCard(context, shop))
        ]));
  }

  Widget _buildTitle(String t) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Text(t,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 35,
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w800,
              height: 0.7)));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final List<Widget> widgetOptions = <Widget>[
      _buildHomePageBody(),
      MyBookingsScreen(
        queueService: _queueService,
        currentUserId: widget.currentUserId,
      ),
      ProfileScreen(authService: widget.authService),
    ];

    return Scaffold(
        backgroundColor: Colors.black,
        body: PageView(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _selectedIndex = i),
            physics: const NeverScrollableScrollPhysics(),
            children: widgetOptions),
        bottomNavigationBar: BottomNavigationBar(
            items: [
              BottomNavigationBarItem(
                  icon: const Icon(Icons.home_filled), label: l10n.home),
              const BottomNavigationBarItem(
                  icon: Icon(Icons.receipt_long_outlined),
                  activeIcon: Icon(Icons.receipt_long),
                  label: 'Antrean'),
              BottomNavigationBarItem(
                  icon: const Icon(Icons.person_outline), label: l10n.profileTab)
            ],
            type: BottomNavigationBarType.fixed,
            backgroundColor: kDarkGrey,
            selectedItemColor: kBrownAccent,
            unselectedItemColor: Colors.white54,
            currentIndex: _selectedIndex,
            showUnselectedLabels: true,
            showSelectedLabels: true,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            onTap: _onItemTapped));
  }
}

class PromoCarousel extends StatefulWidget {
  final BarbershopService barbershopService;
  const PromoCarousel({required this.barbershopService, super.key});
  @override
  State<PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<PromoCarousel>
    with AutomaticKeepAliveClientMixin {
  final PageController _controller = PageController(initialPage: 0);
  Timer? _timer;
  int _current = 0;
  bool _interacting = false;
  List<PromoBanner> _banners = [];
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.barbershopService.getPromoBanners().listen((data) {
      if (mounted) {
        setState(() {
          _banners = data;
        });
        // Start timer only if multiple banners exist
        if (_banners.length > 1 && _timer == null) {
          _timer = Timer.periodic(const Duration(seconds: 4), (t) {
            if (mounted && !_interacting && _controller.hasClients) {
              _current = (_current + 1) % _banners.length;
              _controller.animateToPage(_current,
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.easeInOut);
            }
          });
        } else if (_banners.length <= 1 && _timer != null) {
          _timer?.cancel();
          _timer = null;
        }
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_banners.isEmpty) {
      return Container(
          height: 160,
          margin: const EdgeInsets.symmetric(horizontal: 24.0),
          decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(20)),
          child: const Center(
              child: CircularProgressIndicator(color: Color(0xFFC3A47B))));
    }
    return Column(children: [
      SizedBox(
          height: 160,
          child: Listener(
              onPointerDown: (_) => _interacting = true,
              onPointerUp: (_) => Future.delayed(
                  const Duration(milliseconds: 400),
                  () => _interacting = false),
              child: PageView.builder(
                  controller: _controller,
                  itemCount: _banners.length,
                  onPageChanged: (i) => setState(() => _current = i),
                  itemBuilder: (context, index) {
                    final p = _banners[index];
                    return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Stack(fit: StackFit.expand, children: [
                              AppImage(
                                imageUrl: p.imageUrl,
                                fit: BoxFit.cover,
                                placeholder: Container(color: Colors.black12),
                                errorWidget: const Icon(Icons.broken_image),
                              ),
                              Container(color: Colors.black26),
                              Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(p.title,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 8),
                                        Text(p.subtitle,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14))
                                      ]))
                            ])));
                  })))
    ]);
  }

    @override bool get wantKeepAlive => true;

  }

  

  class _DistanceBadge extends StatelessWidget {

  

    final String distance;

  

  

    const _DistanceBadge({required this.distance});

  

  

    @override

  

    Widget build(BuildContext context) {

  

      return Container(

  

        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),

  

        decoration: BoxDecoration(

  

          color: Colors.black.withValues(alpha: 0.6),

  

          borderRadius: BorderRadius.circular(12),

  

        ),

  

        child: Row(

  

          mainAxisSize: MainAxisSize.min,

  

          children: [

  

            const Icon(Icons.near_me, color: Color(0xFFC3A47B), size: 14),

  

            const SizedBox(width: 4),

  

            Text(

  

              distance,

  

              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),

  

            ),

  

          ],

  

        ),

  

      );

  

    }

  

  }