import 'package:flutter/material.dart';
import 'package:geges_smartbarber/models/barberman.dart';
import 'package:geges_smartbarber/services/barberman_service.dart';
import 'package:intl/intl.dart';

class BarberManagementScreen extends StatefulWidget {
  final String barbershopId;
  final BarbermanService? barbermanService;
  const BarberManagementScreen({super.key, required this.barbershopId, this.barbermanService});
  @override
  State<BarberManagementScreen> createState() => _BarberManagementScreenState();
}

class _BarberManagementScreenState extends State<BarberManagementScreen> with SingleTickerProviderStateMixin {
  late final BarbermanService _svc;
  late TabController _tabController;
  static const Color kBrownAccent = Color(0xFFC3A47B);
  static const Color kDarkSurface = Color(0xFF1E1E1E);
  static const Color kSurface = Colors.black;

  @override
  void initState() {
    super.initState();
    _svc = widget.barbermanService ?? BarbermanService();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() { _tabController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        title: const Text('Kelola Karyawan', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: kSurface,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(controller: _tabController, indicatorColor: kBrownAccent, labelColor: kBrownAccent, unselectedLabelColor: Colors.white54, tabs: const [Tab(text: 'Aktif'), Tab(text: 'Non-Aktif/Hapus')]),
        actions: [IconButton(icon: const Icon(Icons.calendar_month_outlined), tooltip: 'Set Libur Massal', onPressed: _showBulkOffDialog)],
      ),
      floatingActionButton: FloatingActionButton(backgroundColor: kBrownAccent, onPressed: () => _showEditDialog(null), child: const Icon(Icons.add, color: Colors.black)),
      body: TabBarView(controller: _tabController, children: [_buildBarberList(activeOnly: true), _buildBarberList(activeOnly: false)]),
    );
  }

  Widget _buildBarberList({required bool activeOnly}) {
    return StreamBuilder<List<Barberman>>(
      stream: _svc.streamBarbermenByBarbershop(widget.barbershopId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: kBrownAccent));
        var list = (snap.data ?? []).where((b) => activeOnly ? b.isActive : !b.isActive).toList();
        if (list.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.people_outline, size: 64, color: Colors.white24), const SizedBox(height: 16), Text(activeOnly ? 'Belum ada karyawan aktif' : 'Tidak ada karyawan non-aktif', style: const TextStyle(color: Colors.white54))]));
        return ListView.separated(padding: const EdgeInsets.all(16), itemCount: list.length, separatorBuilder: (_, __) => const SizedBox(height: 12), itemBuilder: (c, i) => _barberCard(list[i]));
      },
    );
  }

  Widget _barberCard(Barberman b) {
    return Card(color: kDarkSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.white.withValues(alpha: 0.1))), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        CircleAvatar(backgroundColor: kBrownAccent.withValues(alpha: 0.2), child: Text(b.name.isNotEmpty ? b.name[0].toUpperCase() : '?', style: const TextStyle(color: kBrownAccent))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(b.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)), if (b.isActive) Text(b.onLeave ? 'Sedang Cuti' : 'Bekerja', style: TextStyle(color: b.onLeave ? Colors.orange : Colors.green, fontSize: 12))])),
        IconButton(tooltip: 'Edit data kapster', icon: const Icon(Icons.edit, color: Colors.white70), onPressed: () => _showEditDialog(b)),
        if (b.isActive) IconButton(tooltip: 'Hapus kapster', icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => _confirmDelete(b)) else IconButton(tooltip: 'Pulihkan kapster', icon: const Icon(Icons.restore, color: Colors.greenAccent), onPressed: () => _restoreBarber(b)),
      ]),
      if (b.isActive) ...[const Divider(color: Colors.white12), const SizedBox(height: 8), SizedBox(width: double.infinity, child: OutlinedButton.icon(icon: const Icon(Icons.calendar_month, size: 18), label: const Text('Atur Jadwal Libur & Cuti'), style: OutlinedButton.styleFrom(foregroundColor: kBrownAccent, side: const BorderSide(color: kBrownAccent)), onPressed: () => _showScheduleDialog(b)))]
    ])));
  }

  Future<void> _showEditDialog(Barberman? b) async {
    final nameCtrl = TextEditingController(text: b?.name);
    final ageCtrl = TextEditingController(text: b?.age.toString() == '0' ? '' : b?.age.toString());
    await showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: kDarkSurface, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (ctx) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, left: 20, right: 20, top: 20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(b == null ? 'Tambah Karyawan' : 'Edit Karyawan', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 20),
      TextField(controller: nameCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Nama Lengkap', filled: true, fillColor: Colors.black12)),
      const SizedBox(height: 12),
      TextField(controller: ageCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Umur', filled: true, fillColor: Colors.black12)),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBrownAccent), onPressed: () async {
        if (nameCtrl.text.isEmpty) return;
        await _svc.saveBarberman(Barberman(id: b?.id ?? '', barbershopId: widget.barbershopId, name: nameCtrl.text, rating: b?.rating ?? 5.0, age: int.tryParse(ageCtrl.text) ?? 0, isActive: b?.isActive ?? true, avgDuration: b?.avgDuration ?? 30, imageUrl: b?.imageUrl, offDays: b?.offDays, specificOffDays: b?.specificOffDays ?? [], annualLeaveDays: b?.annualLeaveDays ?? 12, onLeave: b?.onLeave ?? false));
        if (mounted) Navigator.pop(context);
      }, child: const Text('SIMPAN', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))))
    ])));
  }

  Future<void> _confirmDelete(Barberman b) async {
    final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(backgroundColor: kDarkSurface, title: const Text('Non-aktifkan?', style: TextStyle(color: Colors.white)), content: Text('Karyawan ${b.name} akan dipindahkan ke tab Non-Aktif.', style: const TextStyle(color: Colors.white70)), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ya, Non-aktifkan', style: TextStyle(color: Colors.red)))]));
    if (confirm == true) await _svc.deleteBarberman(b.id);
  }

  Future<void> _restoreBarber(Barberman b) async => await _svc.saveBarberman(Barberman(id: b.id, name: b.name, barbershopId: b.barbershopId, imageUrl: b.imageUrl, avgDuration: b.avgDuration, rating: b.rating, isActive: true, offDays: b.offDays, specificOffDays: b.specificOffDays, annualLeaveDays: b.annualLeaveDays, onLeave: b.onLeave, age: b.age));

  Future<void> _showScheduleDialog(Barberman b) async => await showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: kDarkSurface, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (ctx) => _ScheduleEditor(barber: b, service: _svc));

  Future<void> _showBulkOffDialog() async {
    final day = await showDialog<DayOfWeek?>(context: context, builder: (c) { DayOfWeek? sel; return StatefulBuilder(builder: (ctx, setS) => AlertDialog(backgroundColor: kDarkSurface, title: const Text('Set Libur Mingguan Massal', style: TextStyle(color: Colors.white)), content: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Pilih hari untuk dijadikan hari libur bagi SEMUA karyawan aktif.', style: TextStyle(color: Colors.white70)), const SizedBox(height: 16), DropdownButton<DayOfWeek>(value: sel, dropdownColor: kDarkSurface, hint: const Text('Pilih Hari', style: TextStyle(color: Colors.white54)), items: DayOfWeek.values.map((d) => DropdownMenuItem(value: d, child: Text(d.name.toUpperCase(), style: const TextStyle(color: Colors.white)))).toList(), onChanged: (v) => setS(() => sel = v))]), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBrownAccent), onPressed: () => Navigator.pop(c, sel), child: const Text('Terapkan', style: TextStyle(color: Colors.black)))])); });
    
    if (day == null) return;

    await _svc.bulkSetOffDay(widget.barbershopId, day);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Hari libur diterapkan ke semua barber'),
      action: SnackBarAction(label: 'Undo', onPressed: () => _svc.undoBulkSetOffDay(widget.barbershopId, day)),
    ));
  }
}

class _ScheduleEditor extends StatefulWidget {
  final Barberman barber; final BarbermanService service;
  const _ScheduleEditor({required this.barber, required this.service});
  @override State<_ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<_ScheduleEditor> {
  late List<DayOfWeek> _offDays; late List<String> _specificOffDays; late int _annualLeave;
  @override void initState() { super.initState(); _offDays = List.from(widget.barber.offDays ?? []); _specificOffDays = List.from(widget.barber.specificOffDays); _annualLeave = widget.barber.annualLeaveDays; }
  Future<void> _save() async { await widget.service.saveBarberman(Barberman(id: widget.barber.id, name: widget.barber.name, barbershopId: widget.barber.barbershopId, imageUrl: widget.barber.imageUrl, avgDuration: widget.barber.avgDuration, rating: widget.barber.rating, isActive: widget.barber.isActive, onLeave: widget.barber.onLeave, offDays: _offDays, specificOffDays: _specificOffDays, annualLeaveDays: _annualLeave)); if (mounted) Navigator.pop(context); }
  void _toggleDay(DayOfWeek day) => setState(() {
        if (_offDays.contains(day)) {
          _offDays.remove(day);
        } else {
          _offDays.add(day);
        }
      });
  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)), builder: (context, child) => Theme(data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: Color(0xFFC3A47B), onPrimary: Colors.black, surface: Color(0xFF1E1E1E))), child: child!));
    if (picked != null) {
      final str = DateFormat('yyyy-MM-dd').format(picked);
      if (!_specificOffDays.contains(str)) {
        setState(() => _specificOffDays.add(str));
      }
    }
  }
  @override Widget build(BuildContext context) { return Container(height: MediaQuery.of(context).size.height * 0.85, padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Jadwal & Cuti', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)), TextButton(onPressed: _save, child: const Text('SIMPAN', style: TextStyle(color: Color(0xFFC3A47B), fontWeight: FontWeight.bold)))]), const Divider(color: Colors.white24), const SizedBox(height: 10), const Text('1. Libur Mingguan (Rutin)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Wrap(spacing: 8, runSpacing: 8, children: DayOfWeek.values.map((d) { final isSel = _offDays.contains(d); return FilterChip(label: Text(d.name.toUpperCase().substring(0, 3)), selected: isSel, onSelected: (_) => _toggleDay(d), selectedColor: const Color(0xFFC3A47B), checkmarkColor: Colors.black, labelStyle: TextStyle(color: isSel ? Colors.black : Colors.white), backgroundColor: Colors.white10); }).toList()), const SizedBox(height: 24), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('2. Cuti / Libur Khusus', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), IconButton(onPressed: _pickDate, icon: const Icon(Icons.add_circle, color: Color(0xFFC3A47B)))]), const Text('Tanggal spesifik dimana barber ini tidak bisa dibooking.', style: TextStyle(color: Colors.white54, fontSize: 12)), const SizedBox(height: 8), Expanded(child: _specificOffDays.isEmpty ? const Center(child: Text('Tidak ada jadwal cuti khusus', style: TextStyle(color: Colors.white24))) : ListView.builder(itemCount: _specificOffDays.length, itemBuilder: (c, i) { final dateStr = _specificOffDays[i]; return ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.event, color: Colors.white70), title: Text(dateStr, style: const TextStyle(color: Colors.white)), trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () => setState(() => _specificOffDays.removeAt(i)))); })), const SizedBox(height: 16), const Text('3. Kuota Cuti Tahunan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Row(children: [IconButton(onPressed: () => setState(() => _annualLeave > 0 ? _annualLeave-- : null), icon: const Icon(Icons.remove_circle_outline, color: Colors.white54)), Text('$_annualLeave Hari', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), IconButton(onPressed: () => setState(() => _annualLeave++), icon: const Icon(Icons.add_circle_outline, color: Colors.white54))])])); }
}