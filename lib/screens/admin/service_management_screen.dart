import 'package:flutter/material.dart';
import 'package:geges_smartbarber/models/service.dart';
import 'package:geges_smartbarber/services/barbershop_service.dart';

class ServiceManagementScreen extends StatefulWidget {
  final String barbershopId;
  const ServiceManagementScreen({super.key, required this.barbershopId});

  @override
  State<ServiceManagementScreen> createState() => _ServiceManagementScreenState();
}

class _ServiceManagementScreenState extends State<ServiceManagementScreen> {
  final BarbershopService _service = BarbershopService();

  @override
  Widget build(BuildContext context) {
    const Color kBrownAccent = Color(0xFFC3A47B);
    const Color kSurface = Color(0xFF0F0F0F);

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        title: const Text('Manajemen Layanan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: kSurface,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Tambah Layanan Baru',
            icon: const Icon(Icons.add_box_outlined, color: kBrownAccent),
            onPressed: () => _showEditDialog(null),
          ),
        ],
      ),
      body: FutureBuilder<List<Service>>(
        future: _service.getAllServices(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: kBrownAccent));
          final all = snap.data!;
          // In a real multi-tenant app, you'd filter by shop. Here we show all for simplicity or based on a shop list
          // But according to our Barbershop model, it has a list of service IDs.
          
          return FutureBuilder<dynamic>(
            future: _service.getBarbershopById(widget.barbershopId),
            builder: (context, shopSnap) {
              if (!shopSnap.hasData) return const SizedBox();
              final shop = shopSnap.data!;
              final shopServiceIds = Set.from(shop.services);
              final myServices = all.where((s) => shopServiceIds.contains(s.id)).toList();

              if (myServices.isEmpty) return const Center(child: Text('Belum ada layanan', style: TextStyle(color: Colors.white54)));

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: myServices.length,
                itemBuilder: (context, i) {
                  final s = myServices[i];
                  return _serviceTile(s);
                },
              );
            }
          );
        },
      ),
    );
  }

  Widget _serviceTile(Service s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(s.name,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text('Rp ${s.price.toInt()} • ${s.defaultDuration} menit',
            style: const TextStyle(color: Colors.white54)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                icon: const Icon(Icons.edit, color: Colors.white54),
                onPressed: () => _showEditDialog(s)),
            IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () => _confirmDelete(s)),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(Service s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text("Hapus Layanan?", style: TextStyle(color: Colors.white)),
        content: Text("Layanan '${s.name}' akan dihapus dari daftar toko Anda.", style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await _service.removeServiceFromBarbershop(widget.barbershopId, s.id);
              if (!mounted) return;
              // ignore: use_build_context_synchronously
              Navigator.pop(ctx);
              setState(() {});
            }, 
            child: const Text("Hapus", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(Service? s) {
    final nameCtrl = TextEditingController(text: s?.name);
    final descCtrl = TextEditingController(text: s?.description);
    final priceCtrl = TextEditingController(text: s?.price.toInt().toString());
    final durCtrl = TextEditingController(text: s?.defaultDuration.toString());
    bool isActive = s?.isActive ?? true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s == null ? 'Tambah Layanan' : 'Edit Layanan',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              _input("Nama Layanan", nameCtrl),
              const SizedBox(height: 16),
              _input("Deskripsi", descCtrl),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _input("Harga (Rp)", priceCtrl, isNum: true)),
                  const SizedBox(width: 16),
                  Expanded(child: _input("Durasi (Mnt)", durCtrl, isNum: true)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text("Status Aktif",
                      style: TextStyle(color: Colors.white)),
                  const Spacer(),
                  Switch(
                    value: isActive,
                    onChanged: (val) {
                      setModalState(() {
                        isActive = val;
                      });
                    },
                    activeThumbColor: const Color(0xFFC3A47B),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () async {
                  final service = Service(
                    id: s?.id ?? '',
                    name: nameCtrl.text,
                    description: descCtrl.text,
                    price: double.tryParse(priceCtrl.text) ?? 0,
                    defaultDuration: int.tryParse(durCtrl.text) ?? 30,
                    isActive: isActive,
                  );
                  final newId = await _service.saveService(service);
                  // If new, add to barbershop list
                  if (s == null) {
                    await _service.addServiceToBarbershop(widget.barbershopId, newId);
                  }
                  
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                  setState(() {});
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC3A47B),
                    minimumSize: const Size.fromHeight(50)),
                child: const Text("SIMPAN LAYANAN",
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _input(String l, TextEditingController c, {bool isNum = false}) => TextField(
    controller: c, keyboardType: isNum ? TextInputType.number : TextInputType.text,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(labelText: l, labelStyle: const TextStyle(color: Colors.white54), filled: true, fillColor: Colors.white10, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
  );
}
