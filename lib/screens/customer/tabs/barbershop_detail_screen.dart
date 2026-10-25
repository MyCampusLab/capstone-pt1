// NAMA FILE: lib/screens/customer/barbershop_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:geges_smartbarber/models/barbershop.dart';
// Import Halaman Tujuan (Booking)
import 'package:geges_smartbarber/screens/customer/appointment_screen.dart';
// Import 3 Tab
import 'package:geges_smartbarber/screens/customer/tabs/about_tab.dart';
import 'package:geges_smartbarber/screens/customer/tabs/services_tab.dart';
import 'package:geges_smartbarber/screens/customer/tabs/album_tab.dart';

// --- IMPORT BARU ---
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geges_smartbarber/services/barbershop_service.dart';
import 'package:geges_smartbarber/widgets/app_image.dart';
// ------------------

class BarbershopDetailScreen extends StatefulWidget {
  final Barbershop barbershop;
  final FirebaseFirestore? firestore;
  final String? testUserId; // For testing

  const BarbershopDetailScreen({
    super.key, 
    required this.barbershop,
    this.firestore,
    this.testUserId,
  });

  @override
  State<BarbershopDetailScreen> createState() => _BarbershopDetailScreenState();
}

class _BarbershopDetailScreenState extends State<BarbershopDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Warna Tema (sesuai main.dart)
  static const Color kBrownAccent = Color(0xFFC3A47B);
  static const Color kDarkGrey = Color(0xFF1E1E1E);
  static const Color kSurface = Colors.black; // Menambahkan warna surface

  // --- BARU: State untuk data dinamis ---
  late final FirebaseFirestore _firestore;
  late final String? _userId;
  late final BarbershopService _barbershopService;

  bool _isFavorite = false;
  bool _isLoadingFavorite = true;
  late Stream<Barbershop?> _barbershopStream;
  // ---------------------------------

  @override
  void initState() {
    super.initState();
    _firestore = widget.firestore ?? FirebaseFirestore.instance;
    _userId = widget.testUserId ?? FirebaseAuth.instance.currentUser?.uid;
    _barbershopService = BarbershopService(firestore: _firestore);
    _barbershopStream = _barbershopService.streamBarbershopById(widget.barbershop.id);
    
    _tabController = TabController(length: 3, vsync: this);

    // --- BARU: Panggil fungsi untuk mengambil data dinamis ---
    _checkIfFavorite();
    // ----------------------------------------------------
  }

  // --- BARU: Fungsi cek status favorit ---
  Future<void> _checkIfFavorite() async {
    if (_userId == null) {
      if (mounted) setState(() => _isLoadingFavorite = false);
      return;
    }
    try {
      final isFav = await _barbershopService.isFavorite(_userId, widget.barbershop.id);
      if (mounted) {
        setState(() {
          _isFavorite = isFav;
          _isLoadingFavorite = false;
        });
      }
    } catch (e) {
      debugPrint("Error checking favorite: $e");
      if (mounted) setState(() => _isLoadingFavorite = false);
    }
  }

  // --- BARU: Fungsi untuk toggle favorit ---
  Future<void> _toggleFavorite() async {
    if (_userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Silakan login untuk menambah favorit.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_isLoadingFavorite) return; // Mencegah double-tap

    setState(() {
      _isLoadingFavorite = true; // Mulai loading
    });

    try {
      await _barbershopService.toggleFavorite(_userId, widget.barbershop.id);
      
      // Update state local berdasarkan aksi sebelumnya (toggle)
      // Kita bisa cek lagi ke DB atau cukup toggle nilai boolean
      final newStatus = !_isFavorite;
      
      if (mounted) {
        setState(() => _isFavorite = newStatus);
        _showSnackbar(
          newStatus ? 'Ditambahkan ke favorit' : 'Dihapus dari favorit',
          newStatus ? kBrownAccent : Colors.grey,
        );
      }
    } catch (e) {
      debugPrint("Error toggling favorite: $e");
      _showSnackbar('Gagal mengubah favorit', Colors.redAccent);
    } finally {
      if (mounted) {
        setState(() => _isLoadingFavorite = false); // Selesai loading
      }
    }
  }

  void _showSnackbar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // ------------------------------------------

  Widget _buildHeaderImage(String path, String tag) {
    return Hero(
      tag: tag,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AppImage(imageUrl: path, fit: BoxFit.cover),
          Container(color: Colors.black.withValues(alpha: 0.3)), // Overlay gelap
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Barbershop?>(
      stream: _barbershopStream,
      initialData: widget.barbershop,
      builder: (context, snapshot) {
        // --- NULL SAFETY CHECK ---
        // Jika data stream null (dokumen dihapus), tampilkan layar fallback
        if (snapshot.connectionState == ConnectionState.active && snapshot.data == null) {
           return Scaffold(
             backgroundColor: kSurface,
             appBar: AppBar(
               backgroundColor: kDarkGrey,
              leading: IconButton(
                tooltip: 'Kembali',
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
             ),
             body: Center(
               child: Column(
                 mainAxisAlignment: MainAxisAlignment.center,
                 children: const [
                   Icon(Icons.store, size: 64, color: Colors.grey),
                   SizedBox(height: 16),
                   Text(
                     'Barbershop Tidak Ditemukan',
                     style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                   ),
                   SizedBox(height: 8),
                   Text(
                     'Toko ini mungkin sudah tutup atau dihapus.',
                     style: TextStyle(color: Colors.grey),
                   ),
                 ],
               ),
             ),
           );
        }

        final shop = snapshot.data ?? widget.barbershop;

        return Scaffold(
          backgroundColor: kSurface, // Menggunakan warna kSurface
          body: NestedScrollView(
            headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
              return <Widget>[
                // 1. AppBar yang bisa collapse (SliverAppBar)
                SliverAppBar(
                  expandedHeight: 300.0,
                  floating: false,
                  pinned: true,
                  backgroundColor: kDarkGrey,
                  leading: IconButton(
                    tooltip: 'Kembali',
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),

                  // --- Tombol Favorite (DISESUAIKAN) ---
                  actions: [
                    _isLoadingFavorite
                        ? const Padding(
                            // Tampilkan loading kecil
                            padding: EdgeInsets.all(18.0),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            ),
                          )
                        : IconButton(
                            tooltip: _isFavorite ? 'Hapus dari favorit' : 'Tambah ke favorit',
                            icon: Icon(
                              _isFavorite ? Icons.favorite : Icons.favorite_border,
                              color: _isFavorite ? Colors.redAccent : Colors.white,
                            ),
                            onPressed: _toggleFavorite, // Panggil fungsi toggle
                          ),
                  ],
                  // ---------------------------------

                  // --- Gambar Latar (DISESUAIKAN) ---
                  flexibleSpace: FlexibleSpaceBar(
                    background: _buildHeaderImage(shop.imageUrl, 'shop_image_${shop.id}'),
                  ),
                  // ---------------------------------

                  // 2. TabBar (Menempel di bawah AppBar)
                  bottom: TabBar(
                    controller: _tabController,
                    indicatorColor: kBrownAccent,
                    indicatorWeight: 3.0,
                    labelColor: kBrownAccent,
                    unselectedLabelColor: Colors.white70,
                    tabs: const [
                      Tab(text: 'About'),
                      Tab(text: 'Services'),
                      Tab(text: 'Album'),
                    ],
                  ),
                ),
              ];
            },

            // 3. Konten (Body) dari Tab yang dipilih
            body: TabBarView(
              controller: _tabController,
              children: [
                AboutTab(shop: shop),
                ServicesTab(shop: shop),
                AlbumTab(shop: shop),
              ],
            ),
          ),

          // 4. Tombol "Book Now" (Floating di bawah)
          bottomNavigationBar: _buildStickyFooter(context, shop),
        );
      }
    );
  }

  // Widget untuk Footer (Info Barbershop & Tombol Book Now)
  Widget _buildStickyFooter(BuildContext context, Barbershop shop) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0)
          .copyWith(
            bottom:
                MediaQuery.of(context).padding.bottom +
                16.0, // Padding aman area bawah HP
          ),
      decoration: const BoxDecoration(
        color: kDarkGrey,
        border: Border(top: BorderSide(color: Colors.white12, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Info Kiri (Sesuai Desain)
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min, // Agar tinggi container pas
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shop.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.access_time, color: kBrownAccent, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      "${shop.openHour}:00 - ${shop.closeHour}:00",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 16), // Beri jarak
          // Tombol Kanan
          shop.isOpen
              ? ElevatedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AppointmentScreen(barbershop: shop),
                    ),
                  ), // Navigasi ke Halaman Booking
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  ),
                  child: const Text('Book Now'),
                )
              : ElevatedButton(
                  onPressed: null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                    backgroundColor: Colors.redAccent,
                    disabledBackgroundColor: Colors.redAccent,
                  ),
                  child: const Text('TUTUP / CLOSED', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
        ],
      ),
    );
  }
}
