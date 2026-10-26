// lib/screens/customer/appointment_screen.dart
import 'package:flutter/material.dart';
import 'package:geges_smartbarber/config/app_colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:geges_smartbarber/models/service.dart';
import 'package:geges_smartbarber/services/barbershop_service.dart';
import 'package:geges_smartbarber/services/queue_service.dart';
import 'package:geges_smartbarber/screens/customer/payment_screen.dart';
import 'package:geges_smartbarber/models/barbershop.dart';
import 'package:geges_smartbarber/models/barberman.dart';
import 'package:geges_smartbarber/l10n/generated/app_localizations.dart';
import 'package:geges_smartbarber/widgets/app_image.dart';

class AppointmentScreen extends StatefulWidget {
  final Barbershop barbershop;
  final BarbershopService? barbershopService;
  final QueueService? queueService;
  final String? testUserId;
  final String? initialStyleNote; // New parameter for StyleScan integration

  const AppointmentScreen({
    super.key, 
    required this.barbershop, 
    this.barbershopService, 
    this.queueService, 
    this.testUserId,
    this.initialStyleNote,
  });
  @override State<AppointmentScreen> createState() => _AppointmentScreenState();
}

class _AppointmentScreenState extends State<AppointmentScreen> {
  late BarbershopService _barbershopService;
  late final QueueService _queueService;
  static const Color kBrownAccent = AppColors.primary;
  static const Color kSurface = AppColors.background;
  static const Color kCardBg = AppColors.surface;

  int _currentStep = 0; 
  final List<Service> _selectedServices = [];
  final Map<String, String> _serviceNotes = {}; // New: Store notes per service
  bool _hasAutoSelected = false; // New: Ensure auto-selection runs once
  bool _isPremiumChoice = false; 
  Barberman? _selectedBarberman; 
  Barberman? _autoBarberman; 
  late DateTime _selectedDate;
  TimeOfDay? _selectedTime;
  bool _isLoading = false;
  bool _isCheckingAvailability = false;
  bool _isFetchingSlots = false;
  String? _availabilityError;
  List<DateTimeRange> _busySlots = []; 

  int get _servicesPrice => _selectedServices.fold(0, (prev, s) => prev + s.price.toInt());
  int get _selectionFee => _isPremiumChoice ? widget.barbershop.barberSelectionFee : 0;
  int get _totalPrice => _servicesPrice + _selectionFee;
  int get _totalDuration => _selectedServices.fold(0, (prev, s) => prev + s.defaultDuration);

  @override void initState() { super.initState(); _barbershopService = widget.barbershopService ?? BarbershopService(); _queueService = widget.queueService ?? QueueService(); _selectedDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day); _fetchBusySlots(); }

  Future<void> _fetchBusySlots() async {
    if (!mounted) return;
    setState(() { _busySlots = []; _isFetchingSlots = true; });
    try {
      List<DateTimeRange> slots = [];
      if (_isPremiumChoice && _selectedBarberman != null) {
        slots = await _queueService.getBarberBusyTimeRanges(_selectedBarberman!.id, _selectedDate);
      } else if (!_isPremiumChoice) {
        slots = await _queueService.getShopBusySlots(barbershopId: widget.barbershop.id, date: _selectedDate);
      }
      if (mounted) setState(() { _busySlots = slots; _isFetchingSlots = false; });
    } catch (e) { if (mounted) setState(() => _isFetchingSlots = false); }
  }

  bool _isShopOpenOn(DateTime date) {
    if (widget.barbershop.weeklyHolidays.contains(date.weekday % 7)) return false;
    if (widget.barbershop.specificHolidays.contains(DateFormat('yyyy-MM-dd').format(date))) return false;
    return true;
  }

  Future<void> _checkBarberAvailability() async {
    if (_selectedTime == null) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() { _isCheckingAvailability = true; _availabilityError = null; });
    final bookingDateTime = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _selectedTime!.hour, _selectedTime!.minute);
    try {
      if (_isPremiumChoice) {
        if (_selectedBarberman == null) throw l10n.errPickBarberFirst;
        final isAvailable = await _queueService.isSlotAvailable(barbershopId: widget.barbershop.id, barbermanId: _selectedBarberman!.id, bookingTime: bookingDateTime, serviceIds: _selectedServices.map((s) => s.id).toList());
        if (!isAvailable) throw l10n.errBarberBusy;
      } else {
        final fairId = await _queueService.getFairAvailableBarberman(barbershopId: widget.barbershop.id, bookingTime: bookingDateTime, serviceIds: _selectedServices.map((s) => s.id).toList());
        if (fairId == null) throw l10n.errNoFairBarber;
        final b = await _barbershopService.getBarbermanById(fairId);
        setState(() => _autoBarberman = b);
      }
    } catch (e) { setState(() => _availabilityError = e.toString()); } finally { setState(() => _isCheckingAvailability = false); }
  }

  void _nextStep() {
    final l10n = AppLocalizations.of(context)!;
    if (_currentStep < 2) {
      if (_currentStep == 0 && _selectedServices.isEmpty) {
        _showSnack(l10n.errPickService);
        return;
      }
      if (_currentStep == 1 && _isPremiumChoice && _selectedBarberman == null) {
        _showSnack(l10n.errPickBarber);
        return;
      }
      setState(() => _currentStep++);
      if (_currentStep == 2) {
        _fetchBusySlots();
      }
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }
  void _showSnack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (!widget.barbershop.isOpen) {
      return Scaffold(
        backgroundColor: kSurface,
        appBar: AppBar(
          backgroundColor: kSurface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20), 
            onPressed: () => Navigator.pop(context)
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.storefront, size: 64, color: Colors.redAccent),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.errShopClosed(widget.barbershop.name),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.errShopClosedDesc,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 32),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: Text(l10n.backToHome, style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    return PopScope(canPop: false, onPopInvokedWithResult: (didPop, result) { if (didPop) return; if (_currentStep > 0) {
      _prevStep();
    } else {
      Navigator.pop(context);
    } },
      child: Scaffold(
        resizeToAvoidBottomInset: false, // Fix laggy keyboard animation (Layout Thrashing)
        backgroundColor: kSurface, 
        appBar: AppBar(
          backgroundColor: kSurface,
          title: Text(widget.barbershop.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          elevation: 0,
          leading: IconButton(
            tooltip: 'Kembali',
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            onPressed: () => _currentStep > 0 ? _prevStep() : Navigator.pop(context),
          ),
        ),
        body: Column(children: [
          _buildProgressHeader(), 
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom), // Add dynamic padding for keyboard
              child: _buildCurrentStepView()
            )
          ), 
          _buildBottomSummary()
        ])
      )
    );
  }

  Widget _buildProgressHeader() {
    final l10n = AppLocalizations.of(context)!;
    return Container(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 40), child: Row(children: [_stepDot(0, l10n.stepService), _stepLine(0), _stepDot(1, l10n.stepBarber), _stepLine(1), _stepDot(2, l10n.stepSchedule)])); 
  }
  Widget _stepDot(int index, String label) { bool active = _currentStep >= index; return Column(children: [CircleAvatar(radius: 12, backgroundColor: active ? kBrownAccent : Colors.grey[800], child: Text("${index + 1}", style: TextStyle(color: active ? Colors.black : Colors.white54, fontSize: 12, fontWeight: FontWeight.bold))), const SizedBox(height: 4), Text(label, style: TextStyle(color: active ? kBrownAccent : Colors.white24, fontSize: 10))]); }
  Widget _stepLine(int index) { bool active = _currentStep > index; return Expanded(child: Divider(color: active ? kBrownAccent : Colors.grey[800], thickness: 2, indent: 8, endIndent: 8)); }
  Widget _buildCurrentStepView() { switch (_currentStep) { case 0: return _buildServiceStep(); case 1: return _buildBarberStep(); case 2: return _buildScheduleStep(); default: return const SizedBox(); } }

  Widget _buildServiceStep() {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<List<Service>>(future: _barbershopService.getAllServices(), builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: kBrownAccent));
      final shopServices = snap.data!.where((s) => widget.barbershop.services.contains(s.id)).toList();
      
      // Auto-select Haircut if style note exists
      if (widget.initialStyleNote != null && !_hasAutoSelected && shopServices.isNotEmpty) {
        // Find service with "haircut" or "potong" (case insensitive)
        try {
          final haircutService = shopServices.firstWhere(
            (s) => s.name.toLowerCase().contains('haircut') || s.name.toLowerCase().contains('potong'),
            orElse: () => shopServices.first, // Fallback to first service if not found
          );
          
          // Add to selection if not already added
          if (!_selectedServices.any((s) => s.id == haircutService.id)) {
            // We need to schedule this state change to avoid build errors
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _selectedServices.add(haircutService);
                  _serviceNotes[haircutService.id] = widget.initialStyleNote!;
                  _hasAutoSelected = true;
                });
              }
            });
          }
        } catch (_) {}
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.selectServiceTitle, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(l10n.selectServiceSubtitle, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 24),
          ...shopServices.map((s) => _serviceCard(s)),
        ],
      );
    });
  }

  Widget _serviceCard(Service s) {
    bool isSelected = _selectedServices.any((item) => item.id == s.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () { 
          setState(() { 
            isSelected ? _selectedServices.removeWhere((i) => i.id == s.id) : _selectedServices.add(s); 
            if (!isSelected) {
               // If re-selecting, keep note if exists, or clear? Let's keep it.
            } else {
               _serviceNotes.remove(s.id);
            }
          }); 
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? kBrownAccent.withValues(alpha: 0.1) : kCardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? kBrownAccent : Colors.transparent)
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text("${s.defaultDuration} mnt • Rp ${s.price.toInt()}", style: const TextStyle(color: Colors.white54, fontSize: 13))
                      ]
                    )
                  ),
                  Checkbox(
                    value: isSelected,
                    onChanged: (_) { 
                      setState(() { 
                        isSelected ? _selectedServices.removeWhere((i) => i.id == s.id) : _selectedServices.add(s);
                         if (isSelected) _serviceNotes.remove(s.id);
                      }); 
                    },
                    activeColor: kBrownAccent,
                    checkColor: Colors.black
                  )
                ]
              ),
              // Optional Note Field (Enterprise UI)
              if (isSelected) ...[
                const SizedBox(height: 12),
                const Divider(color: Colors.white10),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: _serviceNotes[s.id],
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: "Catatan khusus (opsional)...",
                    hintStyle: const TextStyle(color: Colors.white24),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.3),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    prefixIcon: const Icon(Icons.edit_note, color: kBrownAccent, size: 18),
                  ),
                  onChanged: (val) {
                    _serviceNotes[s.id] = val;
                  },
                ),
              ]
            ],
          )
        )
      )
    );
  }

  Widget _buildBarberStep() {
    final l10n = AppLocalizations.of(context)!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l10n.whoCutsTitle, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 24),
      _choiceCard(icon: Icons.auto_awesome, title: l10n.barberChoiceSystem, subtitle: l10n.barberChoiceSystemDesc, isSelected: !_isPremiumChoice, onTap: () { setState(() { _isPremiumChoice = false; _selectedBarberman = null; _availabilityError = null; }); _fetchBusySlots(); }), const SizedBox(height: 16),
      _choiceCard(icon: Icons.stars, title: l10n.barberChoiceFavorite, subtitle: l10n.barberChoiceFavoriteDesc(widget.barbershop.barberSelectionFee.toString()), isSelected: _isPremiumChoice, onTap: () { setState(() { _isPremiumChoice = true; _availabilityError = null; }); _fetchBusySlots(); }),
      if (_isPremiumChoice) ...[const SizedBox(height: 32), Text(l10n.specialistList, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), const SizedBox(height: 16), _buildBarberList()]
    ]);
  }

  Widget _choiceCard({required IconData icon, required String title, required String subtitle, required bool isSelected, required VoidCallback onTap}) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$title, $subtitle',
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isSelected ? kBrownAccent.withValues(alpha: 0.1) : kCardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isSelected ? kBrownAccent : Colors.transparent),
          ),
          child: Row(
            children: [
              Icon(icon, color: isSelected ? kBrownAccent : Colors.white24, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: isSelected ? kBrownAccent : Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              if (isSelected) const Icon(Icons.check_circle, color: kBrownAccent, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBarberList() {
    return FutureBuilder<List<Barberman>>(future: _barbershopService.getBarbermenByShop(widget.barbershop.id), builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: kBrownAccent));
      final activeBarbers = snap.data!.where((b) => b.isActive).toList();
      return SizedBox(height: 120, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: activeBarbers.length, itemBuilder: (context, i) { 
        final b = activeBarbers[i]; 
        bool isSelected = _selectedBarberman?.id == b.id; 
        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Semantics(
            button: true,
            selected: isSelected,
            label: 'Kapster ${b.name}${isSelected ? ', Terpilih' : ''}',
            child: InkWell(
              onTap: () {
                setState(() => _selectedBarberman = b);
                _fetchBusySlots();
              },
              child: Column(
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: isSelected ? kBrownAccent : Colors.transparent, width: 2),
                      color: Colors.grey[900],
                    ),
                    child: ClipOval(
                      child: AppImage(
                        imageUrl: b.imageUrl,
                        width: 70,
                        height: 70,
                        fit: BoxFit.cover,
                        errorWidget: const Icon(Icons.person, color: Colors.white24),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(b.name, style: TextStyle(color: isSelected ? kBrownAccent : Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ),
        );
      }));
    });
  }

  Widget _buildScheduleStep() {
    final l10n = AppLocalizations.of(context)!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l10n.scheduleTitle, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 24),
      Text(l10n.pickDay, style: const TextStyle(color: Colors.white70, fontSize: 14)), const SizedBox(height: 12), _buildDateRow(), const SizedBox(height: 32),
      Text(l10n.pickTime, style: const TextStyle(color: Colors.white70, fontSize: 14)), const SizedBox(height: 12), _buildTimeGrid(),
      if (_availabilityError != null) ...[const SizedBox(height: 24), Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.error_outline, color: Colors.redAccent), const SizedBox(width: 12), Expanded(child: Text(_availabilityError!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)))]))]
    ]);
  }

  Widget _buildDateRow() {
    return SizedBox(height: 90, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: 14, itemBuilder: (context, i) {
      final date = DateTime.now().add(Duration(days: i)); 
      bool isOpen = _isShopOpenOn(date);
      if (isOpen && _isPremiumChoice && _selectedBarberman != null) { 
        final b = _selectedBarberman!; 
        final dayName = DateFormat('EEEE', 'en_US').format(date).toLowerCase(); 
        if (b.offDays != null && b.offDays!.any((d) => d.name == dayName)) isOpen = false; 
        if (b.specificOffDays.contains(DateFormat('yyyy-MM-dd').format(date))) isOpen = false; 
      }
      bool isSelected = _selectedDate.day == date.day && _selectedDate.month == date.month;
      return Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Semantics(
          button: true,
          selected: isSelected,
          enabled: isOpen,
          label: '${DateFormat('EEEE, d MMMM').format(date)}${isOpen ? '' : ' - Toko Libur'}',
          child: InkWell(
            onTap: isOpen
                ? () {
                    setState(() {
                      _selectedDate = date;
                      _selectedTime = null;
                      _availabilityError = null;
                    });
                    _fetchBusySlots();
                  }
                : null,
            child: Container(
              width: 65,
              decoration: BoxDecoration(
                color: isSelected ? kBrownAccent : (isOpen ? kCardBg : Colors.black26),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(DateFormat('EEE').format(date), style: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('${date.day}', style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  if (!isOpen)
                    Text(AppLocalizations.of(context)!.shopHoliday, style: const TextStyle(color: Colors.redAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
      );
    }));
  }

  Widget _buildTimeGrid() {
    if (_isPremiumChoice && _selectedBarberman != null) {
       final b = _selectedBarberman!;
       final dayName = DateFormat('EEEE', 'en_US').format(_selectedDate).toLowerCase();
       
       bool isOff = false;
       if (b.offDays != null && b.offDays!.any((d) => d.name == dayName)) isOff = true;
       if (b.specificOffDays.contains(DateFormat('yyyy-MM-dd').format(_selectedDate))) isOff = true;
       if (b.onLeave) isOff = true;

       if (isOff) {
         final l10n = AppLocalizations.of(context)!;
         return Center(
           child: Padding(
             padding: const EdgeInsets.symmetric(vertical: 32),
             child: Column(
               children: [
                 const Icon(Icons.event_busy, size: 48, color: Colors.redAccent),
                 const SizedBox(height: 16),
                 Text(
                   l10n.barberOffDay(b.name),
                   style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                 ),
                 const SizedBox(height: 8),
                 Text(l10n.barberOffDayDesc, style: const TextStyle(color: Colors.white54, fontSize: 12)),
               ],
             ),
           ),
         );
       }
    }

    final List<TimeOfDay> times = [];
    for (int h = widget.barbershop.openHour; h < widget.barbershop.closeHour; h++) { times.add(TimeOfDay(hour: h, minute: 0)); times.add(TimeOfDay(hour: h, minute: 30)); }
    return GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.2), itemCount: times.length, itemBuilder: (context, i) {
      if (_isFetchingSlots) return Container(decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(8)), alignment: Alignment.center, child: const SizedBox(height: 10, width: 10, child: CircularProgressIndicator(strokeWidth: 1, color: Colors.white24)));
      final t = times[i]; 
      bool isSelected = _selectedTime == t; 
      
      // LOGIKA WAKTU LAMPAU (REAL-TIME)
      final now = DateTime.now();
      bool isPast = false;
      if (_selectedDate.year == now.year && _selectedDate.month == now.month && _selectedDate.day == now.day) {
        if (t.hour < now.hour || (t.hour == now.hour && t.minute < now.minute)) {
          isPast = true;
        }
      }

      bool isBusy = false;
      if (!isPast && _busySlots.isNotEmpty) {
        final slotStart = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, t.hour, t.minute);
        final slotEnd = slotStart.add(const Duration(minutes: 30));
        
        for (var range in _busySlots) {
          if (slotStart.isBefore(range.end.subtract(const Duration(seconds: 1))) && 
              slotEnd.isAfter(range.start.add(const Duration(seconds: 1)))) {
            isBusy = true;
            break;
          }
        }
      }
      bool isDisabled = isPast || isBusy;
      
      return InkWell(
        onTap: isDisabled ? null : () { 
          setState(() { _selectedTime = t; _availabilityError = null; }); 
          _checkBarberAvailability(); 
        },
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? kBrownAccent : (isDisabled ? Colors.white.withValues(alpha: 0.05) : kCardBg),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? kBrownAccent : Colors.transparent),
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Text(
                "${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}", 
                style: TextStyle(
                  color: isSelected ? Colors.black : (isDisabled ? Colors.white24 : Colors.white), 
                  fontWeight: FontWeight.bold,
                  decoration: isDisabled ? TextDecoration.lineThrough : null,
                  decorationColor: Colors.white24,
                  decorationThickness: 2,
                )
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildBottomSummary() {
    final l10n = AppLocalizations.of(context)!;
    bool canProceed = false; String btnText = l10n.btnNext;
    if (_currentStep == 0 && _selectedServices.isNotEmpty) canProceed = true;
    if (_currentStep == 1) { if (!_isPremiumChoice) canProceed = true; if (_isPremiumChoice && _selectedBarberman != null) canProceed = true; }
    if (_currentStep == 2) { if (_selectedTime != null && _availabilityError == null && !_isCheckingAvailability) { canProceed = true; btnText = l10n.btnBookNow; } }
    return Container(padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(context).padding.bottom), decoration: BoxDecoration(color: kCardBg, border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05)))), child: Row(children: [Expanded(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l10n.totalEst, style: const TextStyle(color: Colors.white54, fontSize: 12)), Text(NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(_totalPrice), style: const TextStyle(color: kBrownAccent, fontSize: 20, fontWeight: FontWeight.bold))])), SizedBox(width: 140, height: 50, child: ElevatedButton(onPressed: (canProceed && !_isLoading) ? (_currentStep == 2 ? _processBooking : _nextStep) : null, style: ElevatedButton.styleFrom(backgroundColor: kBrownAccent, disabledBackgroundColor: Colors.white10, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: _isLoading ? const CircularProgressIndicator(color: Colors.black) : Text(btnText, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold))))]));
  }

  Future<void> _processBooking() async {
    final l10n = AppLocalizations.of(context)!;
    final bdt = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _selectedTime!.hour, _selectedTime!.minute);

    // Enhanced Confirmation Dialog
    bool isAgreed = false; // Variable state untuk checkbox
    bool? confirm = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: const BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Text(l10n.confirmBookingTitle, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      _confirmRow(l10n.labelDate, DateFormat('EEEE, d MMM yyyy').format(bdt), color: Colors.white),
                      _confirmRow(l10n.labelTime, DateFormat('HH:mm').format(bdt), color: Colors.white),
                      _confirmRow(l10n.labelBarber, _isPremiumChoice ? _selectedBarberman?.name ?? '-' : l10n.randomSystem, color: kBrownAccent),
                      const Divider(color: Colors.white10, height: 24),
                      _confirmRow(l10n.labelTotalCost, NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(_totalPrice), isBold: true, color: kBrownAccent),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                const Text('Kebijakan Booking & Refund', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PolicyPoint(text: "Booking ini bersifat mengikat slot waktu Hairstylist."),
                      _PolicyPoint(text: "Keterlambatan lebih dari 15 menit dapat menyebabkan booking hangus."),
                      _PolicyPoint(text: "Pembatalan atau Refund akan dikenakan biaya administrasi sebesar 10% dari total pembayaran.", isWarning: true),
                      _PolicyPoint(text: "Pengembalian dana (refund) diproses setelah disetujui admin."),
                    ],
                  ),
                ),

                const Spacer(),

                Row(
                  children: [
                    Checkbox(
                      value: isAgreed,
                      activeColor: kBrownAccent,
                      checkColor: Colors.black,
                      onChanged: (val) {
                        setModalState(() {
                          isAgreed = val ?? false;
                        });
                      },
                    ),
                    const Expanded(
                      child: Text(
                        "Saya menyetujui Syarat & Ketentuan serta Kebijakan Refund di atas.",
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white54,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(l10n.btnCancel),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isAgreed ? () => Navigator.pop(ctx, true) : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kBrownAccent,
                          foregroundColor: Colors.black,
                          disabledBackgroundColor: Colors.white10,
                          disabledForegroundColor: Colors.white24,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(l10n.btnConfirmBook, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }
      ),
    );

    if (confirm != true) return;
    
    setState(() => _isLoading = true);
    final customerId = widget.testUserId ?? FirebaseAuth.instance.currentUser?.uid;
    final barberId = _isPremiumChoice ? _selectedBarberman!.id : _autoBarberman!.id;
    final orderId = 'ORD-${DateTime.now().millisecondsSinceEpoch}';
    final payload = {
      'barbershop_id': widget.barbershop.id,
      'customer_id': customerId,
      'barberman_id': barberId,
      'service_ids': _selectedServices.map((s) => s.id).toList(),
      'total_price': _totalPrice,
      'barber_selection_fee': _selectionFee,
      'paid_barber_selection': _isPremiumChoice,
      'is_auto_assigned': !_isPremiumChoice,
      'estimated_duration': _totalDuration,
      'booking_time': Timestamp.fromDate(bdt),
      'status': 'awaiting_payment',
      'request_status': 'approved',
      'payment_deadline': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 15))),
      'order_id': orderId,
      'service_notes': _serviceNotes, // New: Pass notes to backend
    };
    try { 
      await _queueService.createQueue(payload); 
      if (!mounted) return; 
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (c) => PaymentScreen(
        orderId: orderId, 
        totalPrice: _totalPrice, 
        barbershopId: widget.barbershop.id, 
        barbermanId: barberId, 
        bookingTime: bdt, 
        paymentDeadline: DateTime.now().add(const Duration(minutes: 15)),
        queueService: widget.queueService,
        testUserId: customerId,
      )));     
    } catch (e) {
      if (mounted) _showSnack("Gagal: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _confirmRow(String l, String v, {bool isBold = false, Color color = Colors.white}) => Padding(padding: const EdgeInsets.only(bottom: 8.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(l, style: const TextStyle(color: Colors.white54)), Text(v, style: TextStyle(color: color, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: isBold ? 16 : 14))]));
}

class _PolicyPoint extends StatelessWidget {
  final String text;
  final bool isWarning;
  const _PolicyPoint({required this.text, this.isWarning = false});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isWarning ? Icons.warning_amber_rounded : Icons.circle, size: isWarning ? 16 : 6, color: isWarning ? Colors.orange : Colors.white54),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: isWarning ? Colors.orange : Colors.white70, fontSize: 12, height: 1.4))),
        ],
      ),
    );
  }
}
