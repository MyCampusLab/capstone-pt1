import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:geges_smartbarber/utils/emvco_qris_helper.dart';
import 'package:geges_smartbarber/models/barbershop.dart';
import 'package:geges_smartbarber/services/barbershop_service.dart';
import 'package:geges_smartbarber/widgets/app_image.dart';
import 'package:geges_smartbarber/services/http_api_client.dart';

class BarbershopSettingsScreen extends StatefulWidget {
  final Barbershop barbershop;
  final BarbershopService? barbershopService;

  const BarbershopSettingsScreen({
    required this.barbershop,
    this.barbershopService,
    super.key,
  });

  @override
  State<BarbershopSettingsScreen> createState() =>
      _BarbershopSettingsScreenState();
}

class _BarbershopSettingsScreenState extends State<BarbershopSettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _googleMapsController;
  late TextEditingController _barberSelectionFeeController;
  late TextEditingController _openHourController;
  late TextEditingController _closeHourController;

  late TextEditingController _instagramController;
  late TextEditingController _whatsappController;
  late TextEditingController _tiktokController;
  late TextEditingController _facebookController;
  late TextEditingController _twitterController;
  late TextEditingController _qrisPayloadController;

  late List<String> _facilities;
  final TextEditingController _facilityController = TextEditingController();

  bool _isLoading = false;
  late final BarbershopService _service;
  
  // Image handling
  File? _imageFile;
  String? _currentImageUrl;
  final ImagePicker _picker = ImagePicker();

  static const Color kBrownAccent = Color(0xFFC3A47B);
  static const Color kDarkSurface = Color(0xFF1E1E1E);

  @override
  void initState() {
    super.initState();
    _service = widget.barbershopService ?? BarbershopService();
    final s = widget.barbershop;
    _nameController = TextEditingController(text: s.name);
    _addressController = TextEditingController(text: s.addres);
    _googleMapsController = TextEditingController(text: s.googleMapsUrl ?? '');
    _barberSelectionFeeController = TextEditingController(text: s.barberSelectionFee.toString());
    _openHourController = TextEditingController(text: s.openHour.toString());
    _closeHourController = TextEditingController(text: s.closeHour.toString());
    
    _instagramController = TextEditingController(text: s.instagramUrl ?? '');
    _whatsappController = TextEditingController(text: s.whatsappNumber ?? '');
    _tiktokController = TextEditingController(text: s.tiktokUrl ?? '');
    _facebookController = TextEditingController(text: s.facebookUrl ?? '');
    _twitterController = TextEditingController(text: s.twitterUrl ?? '');
    _qrisPayloadController = TextEditingController(
      text: s.qrisRawPayload ?? EmvcoQrisHelper.defaultSampleStaticQris,
    );
    
    _facilities = List.from(s.facilities);
    _currentImageUrl = s.imageUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _googleMapsController.dispose();
    _barberSelectionFeeController.dispose();
    _openHourController.dispose();
    _closeHourController.dispose();
    _instagramController.dispose();
    _whatsappController.dispose();
    _tiktokController.dispose();
    _facebookController.dispose();
    _twitterController.dispose();
    _qrisPayloadController.dispose();
    _facilityController.dispose();
    super.dispose();
  }

  void _addFacility() {
    final text = _facilityController.text.trim();
    if (text.isNotEmpty && !_facilities.contains(text)) {
      setState(() {
        _facilities.add(text);
        _facilityController.clear();
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        imageQuality: 70,
      );
      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengambil gambar: $e')),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    try {
      String? base64Image;
      if (_imageFile != null) {
        final bytes = await _imageFile!.readAsBytes();
        // Cek ukuran, jika terlalu besar mungkin perlu warning atau compress lagi
        if (bytes.length > 1000000) { // Limit roughly 1MB
           if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('Gambar terlalu besar (>1MB). Mohon pilih gambar yang lebih kecil.'), backgroundColor: Colors.red),
             );
             setState(() => _isLoading = false);
             return;
           }
        }
        base64Image = base64Encode(bytes);
      }

      final Map<String, dynamic> updates = {
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim(),
        'google_maps_url': _googleMapsController.text.trim(),
        'barber_selection_fee': int.tryParse(_barberSelectionFeeController.text) ?? 5000,
        'open_hour': int.tryParse(_openHourController.text) ?? 9,
        'close_hour': int.tryParse(_closeHourController.text) ?? 21,
        'instagram_url': _instagramController.text.trim(),
        'whatsapp_number': _whatsappController.text.trim(),
        'tiktok_url': _tiktokController.text.trim(),
        'facebook_url': _facebookController.text.trim(),
        'twitter_url': _twitterController.text.trim(),
        'qris_raw_payload': _qrisPayloadController.text.trim(),
        'facilities': _facilities,
      };
      if (base64Image != null) {
        updates['imageUrl'] = base64Image;
      }

      await _service.updateBarbershopSettings(widget.barbershop.id, updates);
      final qrisRaw = _qrisPayloadController.text.trim();
      if (qrisRaw.isNotEmpty) {
        try {
          final api = HttpApiClient();
          await api.put('/api/payments/${widget.barbershop.id}/qris-config', {
            'qrisRawPayload': qrisRaw,
          });
          api.close();
        } catch (_) {}
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil toko berhasil diperbarui!')),
        );
        setState(() => _isLoading = false);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Manage Barbershop', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: kBrownAccent,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- IMAGE PICKER SECTION ---
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: kDarkSurface,
                          shape: BoxShape.circle,
                          border: Border.all(color: kBrownAccent, width: 2),
                        ),
                        child: _imageFile != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(120),
                                child: Image.file(_imageFile!, fit: BoxFit.cover),
                              )
                            : (_currentImageUrl != null && _currentImageUrl!.isNotEmpty)
                                ? AppImage(
                                    imageUrl: _currentImageUrl,
                                    borderRadius: BorderRadius.circular(120),
                                    fit: BoxFit.cover,
                                  )
                                : const Icon(Icons.add_a_photo, color: kBrownAccent, size: 40),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.edit, color: kBrownAccent, size: 16),
                      label: const Text('Ubah Foto Profil', style: TextStyle(color: kBrownAccent)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              _buildSectionTitle('Basic Information'),
              const SizedBox(height: 15),
              _buildTextField(_nameController, 'Barbershop Name', Icons.storefront, validator: (v) => v == null || v.isEmpty ? 'Wajib diisi' : null),
              const SizedBox(height: 15),
              _buildTextField(_addressController, 'Address Description', Icons.location_on_outlined, maxLines: 2, validator: (v) => v == null || v.isEmpty ? 'Wajib diisi' : null),
              const SizedBox(height: 15),
              _buildTextField(_googleMapsController, 'Google Maps URL (Link)', Icons.map_outlined),
              const SizedBox(height: 15),
              _buildTextField(_barberSelectionFeeController, 'Barber Selection Fee (Special Order)', Icons.payments_outlined, keyboardType: TextInputType.number),
              
              const SizedBox(height: 30),
              _buildSectionTitle('Working Hours (24h format)'),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(child: _buildTextField(_openHourController, 'Open Hour', Icons.login, keyboardType: TextInputType.number, 
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n < 0 || n > 23) return '0-23';
                      return null;
                    }
                  )),
                  const SizedBox(width: 15),
                  Expanded(child: _buildTextField(_closeHourController, 'Close Hour', Icons.logout, keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n < 0 || n > 23) return '0-23';
                      return null;
                    }
                  )),
                ],
              ),

              const SizedBox(height: 30),
              _buildSectionTitle('Facilities'),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(child: _buildTextField(_facilityController, 'Add Facility', Icons.add_box_outlined)),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _addFacility,
                    style: ElevatedButton.styleFrom(backgroundColor: kBrownAccent, foregroundColor: Colors.black),
                    child: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              _facilities.isEmpty 
                  ? const Text('Belum ada fasilitas ditambahkan.', style: TextStyle(color: Colors.white38, fontStyle: FontStyle.italic))
                  : Wrap(
                spacing: 8,
                children: _facilities.map((f) => Chip(
                  label: Text(f),
                  backgroundColor: kDarkSurface,
                  labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
                  deleteIcon: const Icon(Icons.close, size: 14, color: Colors.redAccent),
                  onDeleted: _isLoading ? null : () => setState(() => _facilities.remove(f)),
                )).toList(),
              ),

              const SizedBox(height: 30),
              _buildSectionTitle('Social Media Links'),
              const SizedBox(height: 15),
              _buildTextField(_instagramController, 'Instagram URL', Icons.camera_alt_outlined),
              const SizedBox(height: 12),
              _buildTextField(_whatsappController, 'WhatsApp (e.g. 62812...)', Icons.chat_outlined),
              const SizedBox(height: 12),
              _buildTextField(_tiktokController, 'TikTok URL', Icons.music_note_outlined),
              const SizedBox(height: 12),
              _buildTextField(_facebookController, 'Facebook URL', Icons.facebook_outlined),
              const SizedBox(height: 12),
              _buildTextField(_twitterController, 'Twitter/X URL', Icons.close),


              const SizedBox(height: 30),
              _buildSectionTitle('QRIS Dinamis & Jembatan DompetKu (0% Potongan)'),
              const SizedBox(height: 8),
              const Text(
                'Masukkan payload EMVCo QRIS Statis toko Anda (diawali 000201). Sistem otomatis mengubahnya menjadi QRIS Dinamis ber-nominal unik tanpa biaya potongan gateway.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 12),
              _buildTextField(
                _qrisPayloadController,
                'Payload EMVCo QRIS Statis (000201...)',
                Icons.qr_code_2_rounded,
                maxLines: 3,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  return EmvcoQrisHelper.validateStaticQris(v);
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  String webhookUrl =
                      widget.barbershop.dompetkuWebhookUrl ??
                      'http://127.0.0.1:4000/api/payments/webhook/${widget.barbershop.id}?secret=dompetku-febrian-secret-2026';
                  try {
                    final api = HttpApiClient();
                    final cfg = await api.get(
                      '/api/payments/${widget.barbershop.id}/dompetku-config',
                    );
                    api.close();
                    if (cfg is Map && cfg['smartPasteUrl'] is String) {
                      webhookUrl = cfg['smartPasteUrl'] as String;
                    }
                  } catch (_) {}
                  await Clipboard.setData(ClipboardData(text: webhookUrl));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('URL Webhook DompetKu disalin: $webhookUrl'),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded, color: kBrownAccent, size: 18),
                label: const Text(
                  'Salin URL Webhook DompetKu (Smart Paste)',
                  style: TextStyle(color: kBrownAccent, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: kBrownAccent),
                  minimumSize: const Size(double.infinity, 46),
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kBrownAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.black)
                    : const Text('SAVE ALL CHANGES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: const TextStyle(color: kBrownAccent, fontSize: 18, fontWeight: FontWeight.bold));
  }

  Widget _buildTextField(TextEditingController ctrl, String label, IconData icon, {int maxLines = 1, String? Function(String?)? validator, TextInputType keyboardType = TextInputType.text}) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      enabled: !_isLoading, // Disable when loading
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 14),
        prefixIcon: Icon(icon, color: kBrownAccent, size: 20),
        filled: true,
        fillColor: kDarkSurface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      validator: validator,
    );
  }
}