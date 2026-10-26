// lib/screens/admin/live_queue_screen.dart
import 'dart:async';
import 'package:geges_smartbarber/config/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geges_smartbarber/models/queue.dart';
import 'package:geges_smartbarber/models/service.dart';
import 'package:geges_smartbarber/models/barberman.dart';
import 'package:geges_smartbarber/services/barbershop_service.dart';
import 'package:geges_smartbarber/services/queue_service.dart';
import 'package:geges_smartbarber/widgets/admin/queue_card.dart';
import 'package:geges_smartbarber/widgets/utility/loading_widget.dart';

const Color kBrownAccent = AppColors.primary;
const Color kDarkSurface = AppColors.surface;
const Color kBlack = AppColors.background;

class LiveQueueScreen extends StatefulWidget {
  final String barbershopId;
  final List<String> initialFilter;
  final String title;
  const LiveQueueScreen({super.key, required this.barbershopId, required this.initialFilter, this.title = 'Antrean Live'});
  @override State<LiveQueueScreen> createState() => _LiveQueueScreenState();
}

class _LiveQueueScreenState extends State<LiveQueueScreen> {
  final QueueService _queueService = QueueService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final BarbershopService _barbershopService = BarbershopService();
  List<Barberman> _shopBarbers = [];
  String? _selectedBarberId;
  
  late List<String> _currentStatusFilter;
  String _activeFilterLabel = 'Live';
  Timer? _timer;

  // Cache for names and details
  final Map<String, String> _nameCache = {};
  final Map<String, Map<String, dynamic>> _detailsMap = {};
  bool _isLoadingDetails = false;

  @override void initState() {
    super.initState();
    _currentStatusFilter = List.from(widget.initialFilter);
    if (_currentStatusFilter.contains('booked')) _activeFilterLabel = 'Live';
    
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) { setState(() {}); _queueService.cancelExpiredBookings(widget.barbershopId); }
    });
    _loadShopBarbers();
  }

  @override void dispose() { _timer?.cancel(); super.dispose(); }

  Future<void> _startService(Queue q) async { try { await _queueService.startService(q.id); } catch (_) {} }
  Future<void> _finishService(Queue q) async { try { await _queueService.finishService(q.id, q.startTime); } catch (_) {} }
  Future<void> _cancelQueue(Queue q) async { try { await _queueService.cancelQueue(q.id); } catch (_) {} }
  Future<void> _loadShopBarbers() async {
    try {
      final barbers = await _barbershopService.getBarbermenByShop(widget.barbershopId);
      if (mounted) setState(() => _shopBarbers = barbers);
    } catch (_) {}
  }

  void _updateFilter(String label, List<String> statuses) {
    setState(() {
      _activeFilterLabel = label;
      _currentStatusFilter = statuses;
      // We don't clear detailsMap to keep cache, but we'll fetch new ones if needed
    });
  }

  Future<void> _fetchBulkDetails(List<Queue> queues) async {
    if (queues.isEmpty) return;
    
    final customerIds = queues.map((q) => q.customerId).toSet();
    final barberIds = queues.map((q) => q.barbermanId).toSet();
    final allServiceIds = queues.expand((q) => q.serviceIds ?? <String>[]).toSet();

    final customersToFetch = customerIds.where((id) => !_nameCache.containsKey('c_$id')).toList();
    final barbersToFetch = barberIds.where((id) => !_nameCache.containsKey('b_$id')).toList();
    final servicesToFetch = allServiceIds.where((id) => !_nameCache.containsKey('s_$id')).toList();

    if (customersToFetch.isEmpty && barbersToFetch.isEmpty && servicesToFetch.isEmpty) {
      _updateDetailsMap(queues);
      return;
    }

    if (mounted) setState(() => _isLoadingDetails = true);

    try {
      await Future.wait([
        if (customersToFetch.isNotEmpty) _fetchDocs('users', customersToFetch, 'c_'),
        if (barbersToFetch.isNotEmpty) _fetchDocs('barbermen', barbersToFetch, 'b_'),
        if (servicesToFetch.isNotEmpty) _fetchDocs('services', servicesToFetch, 's_'),
      ]);
      _updateDetailsMap(queues);
    } catch (e) {
      debugPrint('Error bulk fetching in LiveQueue: $e');
    } finally {
      if (mounted) setState(() => _isLoadingDetails = false);
    }
  }

  Future<void> _fetchDocs(String collection, List<String> ids, String cachePrefix) async {
    await Future.wait(ids.map((id) async {
      try {
        final doc = await _firestore.collection(collection).doc(id).get();
        final data = doc.data();
        _nameCache['$cachePrefix$id'] = data?['name'] ?? 'Unknown';
        if (cachePrefix == 'c_' && data?['photoBase64'] != null) {
          _nameCache['cp_$id'] = data!['photoBase64'];
        }
      } catch (_) {
        _nameCache['$cachePrefix$id'] = 'Unknown';
      }
    }));
  }

  void _updateDetailsMap(List<Queue> queues) {
    for (final q in queues) {
      final customer = _nameCache['c_${q.customerId}'] ?? 'Pelanggan';
      final barber = _nameCache['b_${q.barbermanId}'] ?? 'Barber Unknown';
      final photo = _nameCache['cp_${q.customerId}'];
      
      List<Service> services = [];
      if (q.serviceIds != null) {
        for (var sid in q.serviceIds!) {
          final name = _nameCache['s_$sid'];
          if (name != null) {
            services.add(Service(id: sid, name: name, description: '', price: 0.0, defaultDuration: 0, isActive: true));
          }
        }
      }
      
      _detailsMap[q.id] = {
        'customerName': customer,
        'barberName': barber,
        'customerPhoto': photo,
        'services': services,
      };
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1)), 
        backgroundColor: kBlack, 
        iconTheme: const IconThemeData(color: Colors.white), 
        elevation: 0,
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: _buildFilterBar(),
        ),
      ),
      body: SafeArea(child: StreamBuilder<List<Queue>>(
        stream: _queueService.streamQueuesForBarbershop(
          widget.barbershopId, 
          statusFilter: _currentStatusFilter.isEmpty ? null : _currentStatusFilter
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
          if (snapshot.connectionState == ConnectionState.waiting && _detailsMap.isEmpty) return const LoadingWidget();
          
          var list = snapshot.data ?? [];
          if (_selectedBarberId != null) {
            list = list.where((q) => q.barbermanId == _selectedBarberId).toList();
          }
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_rounded, size: 64, color: Colors.white.withValues(alpha: 0.1)),
                  const SizedBox(height: 16),
                  Text('Tidak ada data ${_activeFilterLabel.toLowerCase()}', style: const TextStyle(color: Colors.white24, fontSize: 16)),
                ],
              ),
            );
          }

          // Trigger bulk fetch
          WidgetsBinding.instance.addPostFrameCallback((_) {
            bool needsFetch = list.any((q) => !_detailsMap.containsKey(q.id));
            if (needsFetch && !_isLoadingDetails) {
              _fetchBulkDetails(list);
            }
          });

          // Sort: Ongoing first, then by time
          list.sort((a, b) {
            if (a.status == QueueStatus.ongoing && b.status != QueueStatus.ongoing) return -1;
            if (b.status == QueueStatus.ongoing && a.status != QueueStatus.ongoing) return 1;
            return a.bookingTime.toDate().compareTo(b.bookingTime.toDate());
          });

          return ListView.builder(
            padding: const EdgeInsets.all(16), 
            itemCount: list.length, 
            itemBuilder: (context, i) {
              final q = list[i];
              final d = _detailsMap[q.id];
              return QueueCard(
                key: ValueKey(q.id),
                queue: q, 
                // Pass cached details if available
                initialCustomerName: d?['customerName'],
                initialBarberName: d?['barberName'],
                initialCustomerPhoto: d?['customerPhoto'],
                initialServices: d?['services'],
                onStartService: () => _startService(q), 
                onFinishService: () => _finishService(q), 
                onCancelQueue: () => _cancelQueue(q)
              );
            }
          );
        },
      )),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _filterChip('Live', ['booked', 'ongoing']),
                _filterChip('Pending', ['waiting', 'awaiting_payment', 'cancellation_requested']),
                _filterChip('Selesai', ['served']),
                _filterChip('Batal', ['cancelled']),
                _filterChip('Semua', []),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _barberChip('Semua Kursi', null),
                ..._shopBarbers.map((b) => _barberChip('Kursi: ${b.name}', b.id)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _barberChip(String label, String? barberId) {
    final bool isSelected = _selectedBarberId == barberId;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: Icon(
          barberId == null ? Icons.groups_outlined : Icons.chair_outlined,
          size: 14,
          color: isSelected ? Colors.black : AppColors.primary,
        ),
        label: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white70,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        selected: isSelected,
        onSelected: (val) {
          if (val) setState(() => _selectedBarberId = barberId);
        },
        selectedColor: AppColors.primary,
        backgroundColor: AppColors.surface,
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.border,
          width: 0.8,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        showCheckmark: false,
      ),
    );
  }

  Widget _filterChip(String label, List<String> statuses) {
    final bool isSelected = _activeFilterLabel == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white70,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        selected: isSelected,
        onSelected: (val) {
          if (val) _updateFilter(label, statuses);
        },
        selectedColor: AppColors.primary,
        backgroundColor: AppColors.surface,
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.border,
          width: 0.8,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        showCheckmark: false,
      ),
    );
  }
}