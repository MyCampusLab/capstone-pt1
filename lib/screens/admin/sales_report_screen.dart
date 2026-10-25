// lib/screens/admin/sales_report_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geges_smartbarber/models/queue.dart';
import 'package:geges_smartbarber/services/queue_service.dart';

const Color kBrownAccent = Color(0xFFC3A47B);
const Color kDarkGrey = Color(0xFF1E1E1E);
const Color kSurface = Colors.black;
const Color kGreenSuccess = Color(0xFF81C784);

class SalesReportScreen extends StatefulWidget {
  final String barbershopId;
  final QueueService? queueService;
  const SalesReportScreen({super.key, required this.barbershopId, this.queueService});

  @override
  State<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends State<SalesReportScreen> {
  late final QueueService _queueService;
  String _filterType = 'Harian'; // Harian, Mingguan, Bulanan
  DateTime _selectedDate = DateTime.now();
  
  @override
  void initState() {
    super.initState();
    _queueService = widget.queueService ?? QueueService();
  }

  @override
  Widget build(BuildContext context) {
    // Determine Date Range
    DateTime start, end;
    if (_filterType == 'Harian') {
      start = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      end = start.add(const Duration(days: 1));
    } else if (_filterType == 'Mingguan') {
      // Start from Monday
      start = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day).subtract(Duration(days: _selectedDate.weekday - 1));
      end = start.add(const Duration(days: 7));
    } else {
      // Monthly
      start = DateTime(_selectedDate.year, _selectedDate.month, 1);
      end = DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
    }

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        title: const Text('Laporan Penjualan', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: kSurface,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Pilih Tanggal Laporan',
            icon: const Icon(Icons.calendar_today),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                builder: (context, child) {
                  return Theme(
                    data: ThemeData.dark().copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: kBrownAccent,
                        onPrimary: Colors.black,
                        surface: kDarkGrey,
                      ),
                    ),
                    child: child!,
                  );
                }
              );
              if (picked != null) setState(() => _selectedDate = picked);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Tabs
          Container(
            height: 50,
            margin: const EdgeInsets.symmetric(vertical: 10),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: ['Harian', 'Mingguan', 'Bulanan'].map((type) {
                final isSel = _filterType == type;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: ChoiceChip(
                    label: Text(type),
                    selected: isSel,
                    onSelected: (val) => setState(() => _filterType = type),
                    selectedColor: kBrownAccent,
                    labelStyle: TextStyle(color: isSel ? Colors.black : Colors.white),
                    backgroundColor: kDarkGrey,
                  ),
                );
              }).toList(),
            ),
          ),

          // Date Display
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              _getDateLabel(start, end),
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ),

          // Main Content
          Expanded(
            child: StreamBuilder<List<Queue>>(
              // Query queues for this shop with relevant statuses for revenue
              stream: _queueService.streamQueuesForBarbershop(
                widget.barbershopId,
                statusFilter: ['served', 'refund_completed', 'cancelled'], 
                limit: 200, 
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: kBrownAccent));
                }
                
                final allData = snapshot.data ?? [];
                
                // Filter by date & revenue eligibility
                final filtered = allData.where((q) {
                  final dt = q.bookingTime.toDate();
                  final isDateMatch = dt.isAfter(start) && dt.isBefore(end);
                  if (!isDateMatch) return false;
                  
                  // Keep if served OR refunded (we get 10% from refunded)
                  return q.status == QueueStatus.served || (q.isRefunded == true);
                }).toList();

                // Sort newest first
                filtered.sort((a, b) => b.bookingTime.compareTo(a.bookingTime));

                // Calc Totals
                int totalRev = 0;
                for (var q in filtered) {
                  if (q.status == QueueStatus.served) {
                    totalRev += (q.totalPrice ?? 0);
                  } else if (q.isRefunded == true) {
                    totalRev += ((q.totalPrice ?? 0) * 0.1).round();
                  }
                }

                return Column(
                  children: [
                    // Summary Cards
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Expanded(child: _buildSummaryCard('Pendapatan', 'Rp ${NumberFormat('#,###').format(totalRev)}', Colors.green)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildSummaryCard('Transaksi', '${filtered.length}', Colors.blue)),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Transaction List
                    Expanded(
                      child: filtered.isEmpty 
                      ? const Center(child: Text('Tidak ada data penjualan', style: TextStyle(color: Colors.white24)))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                          itemBuilder: (context, i) {
                            final q = filtered[i];
                            final isRefund = q.isRefunded == true;
                            final amount = isRefund ? ((q.totalPrice ?? 0) * 0.1).round() : (q.totalPrice ?? 0);
                            
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: kDarkGrey,
                                child: Text(
                                  DateFormat('d').format(q.bookingTime.toDate()),
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ),
                              title: Text(
                                q.customerName ?? 'Customer',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                isRefund 
                                  ? 'Refund (Fee 10%) • ${DateFormat('HH:mm').format(q.bookingTime.toDate())}'
                                  : 'Layanan Selesai • ${DateFormat('HH:mm').format(q.bookingTime.toDate())}',
                                style: TextStyle(color: isRefund ? Colors.orange : Colors.white54, fontSize: 12),
                              ),
                              trailing: Text(
                                '+ Rp ${NumberFormat('#,###').format(amount)}',
                                style: const TextStyle(color: kGreenSuccess, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            );
                          },
                        ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getDateLabel(DateTime start, DateTime end) {
    if (_filterType == 'Harian') return DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(start);
    if (_filterType == 'Mingguan') return '${DateFormat('d MMM').format(start)} - ${DateFormat('d MMM yyyy').format(end.subtract(const Duration(days: 1)))}';
    return DateFormat('MMMM yyyy', 'id_ID').format(start);
  }

  Widget _buildSummaryCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kDarkGrey,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
