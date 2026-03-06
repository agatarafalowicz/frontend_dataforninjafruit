import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:frontend_dataforninjafruit/models/user.dart';

class Movement {
  final int id;
  final String name;
  final IconData icon;

  const Movement({
    required this.id,
    required this.name,
    required this.icon,
  });
}

class Measurement {
  final String id;
  final String movement;
  final String side;
  final double duration;
  final int timestamp;

  Measurement({
    required this.id,
    required this.movement,
    required this.side,
    required this.duration,
    required this.timestamp,
  });

  factory Measurement.fromJson(Map<String, dynamic> json) {
    return Measurement(
      id: json['id'] as String,
      movement: json['movement'] as String,
      side: json['side'] as String,
      duration: (json['duration'] as num).toDouble(),
      timestamp: json['timestamp'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'movement': movement,
      'side': side,
      'duration': duration,
      'timestamp': timestamp,
    };
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<Movement> _movements = const [
    Movement(id: 1, name: 'Fala', icon: Icons.waves),
    Movement(id: 2, name: 'Machanie', icon: Icons.pan_tool_alt),
    Movement(id: 3, name: 'Okrąg (zgodnie ze wskazówkami zegara)', icon: Icons.rotate_right),
    Movement(id: 4, name: 'Okrąg (przeciwnie do wskazówek zegara)', icon: Icons.rotate_left),
    Movement(id: 5, name: 'Góra-dół', icon: Icons.swap_vert),
    Movement(id: 6, name: 'Inne ruchy', icon: Icons.more_horiz),
  ];

  Movement? _selectedMovement;
  String _selectedSide = 'right';
  bool _isRecording = false;
  double _recordingTime = 0;
  Timer? _timer;
  List<Measurement> _measurements = [];
  AppUser? _currentUser;

  @override
  void initState() {
    super.initState();
    _selectedMovement = _movements.first;
    _loadCurrentUser();
    _loadMeasurements();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<SharedPreferences> _prefs() {
    return SharedPreferences.getInstance();
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await _prefs();
    final value = prefs.getString('currentUser');
    if (value == null || value.isEmpty) return;
    try {
      final user = AppUser.fromJsonString(value);
      setState(() {
        _currentUser = user;
      });
    } catch (_) {}
  }

  Future<void> _loadMeasurements() async {
    final prefs = await _prefs();
    final value = prefs.getString('measurements');
    if (value == null || value.isEmpty) return;
    try {
      final dynamic parsed = jsonDecode(value);
      if (parsed is List) {
        final list = parsed
            .whereType<Map<String, dynamic>>()
            .map((e) => Measurement.fromJson(e))
            .toList();
        setState(() {
          _measurements = list;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveMeasurements() async {
    final prefs = await _prefs();
    final data = _measurements.map((e) => e.toJson()).toList();
    await prefs.setString('measurements', jsonEncode(data));
  }

  String _formatTime(double seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds.truncate() % 60;
    final mm = mins.toString().padLeft(2, '0');
    final ss = secs.toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  void _toggleRecording() {
    if (_isRecording) {
      setState(() {
        _isRecording = false;
      });
      _timer?.cancel();
      final measurement = Measurement(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        movement: _selectedMovement?.name ?? '',
        side: _selectedSide,
        duration: _recordingTime,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      setState(() {
        _measurements = [..._measurements, measurement];
      });
      _saveMeasurements();
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        setState(() {
          _recordingTime = 0;
        });
      });
    } else {
      setState(() {
        _recordingTime = 0;
        _isRecording = true;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(milliseconds: 10), (timer) {
        setState(() {
          final next = _recordingTime + 0.01;
          _recordingTime = double.parse(next.toStringAsFixed(2));
        });
      });
    }
  }

  Future<void> _confirmDeleteMeasurement(Measurement measurement) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Czy na pewno usunąć?'),
          content: const Text(
            'Ta operacja jest nieodwracalna. Pomiar zostanie trwale usunięty.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Nie'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Tak'),
            ),
          ],
        );
      },
    );
    if (result == true) {
      setState(() {
        _measurements =
            _measurements.where((m) => m.id != measurement.id).toList();
      });
      _saveMeasurements();
    }
  }

  Future<void> _confirmDeleteAll() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Czy na pewno usunąć wszystkie pomiary?'),
          content: const Text(
            'Ta operacja jest nieodwracalna. Wszystkie pomiary zostaną trwale usunięte.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Nie'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Tak'),
            ),
          ],
        );
      },
    );
    if (result == true) {
      setState(() {
        _measurements = [];
      });
      final prefs = await _prefs();
      await prefs.remove('measurements');
    }
  }

  Future<void> _exportFile() async {
    if (_measurements.isEmpty) return;
    final buffer = StringBuffer();
    buffer.writeln('Ruch,Strona,Czas trwania (s),Data');
    for (final m in _measurements) {
      final date = DateTime.fromMillisecondsSinceEpoch(m.timestamp).toLocal();
      final side = m.side == 'left' ? 'Lewa' : 'Prawa';
      buffer.writeln(
        '"${m.movement}","$side",${m.duration.toStringAsFixed(2)},"$date"',
      );
    }
    final csv = buffer.toString();
    final bytes = Uint8List.fromList(utf8.encode(csv));
    final file = XFile.fromData(
      bytes,
      mimeType: 'text/csv',
      name: 'pomiary_${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    await Share.shareXFiles([file]);
  }

  Future<void> _logout() async {
    final prefs = await _prefs();
    await prefs.remove('currentUser');
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFE0E7FF),
              Color(0xFFEDE9FE),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeaderCard(context),
                        const SizedBox(height: 16),
                        _buildMovementCard(context),
                        const SizedBox(height: 16),
                        _buildControlCard(context),
                        if (_measurements.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _buildMeasurementsCard(context),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    final name = _currentUser?.name.isNotEmpty == true
        ? _currentUser!.name
        : _currentUser?.email ?? '';
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Zalogowany jako',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Wyloguj'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMovementCard(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Wybierz ruch',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.9,
              ),
              itemCount: _movements.length,
              itemBuilder: (context, index) {
                final movement = _movements[index];
                final selected = _selectedMovement?.id == movement.id;
                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedMovement = movement;
                    });
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFFDBEAFE) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? const Color(0xFF3B82F6) : const Color(0xFFE5E7EB),
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: FittedBox(
                            child: Icon(
                              movement.icon,
                              color: const Color(0xFF4B5563),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          movement.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF374151),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlCard(BuildContext context) {
    final isRecording = _isRecording;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _toggleRecording,
              style: ElevatedButton.styleFrom(
                backgroundColor: isRecording ? const Color(0xFFEF4444) : const Color(0xFF22C55E),
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: Icon(isRecording ? Icons.stop : Icons.play_arrow),
              label: Text(isRecording ? 'Zakończ ruch' : 'Rozpocznij ruch'),
            ),
            if (isRecording) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('🔴 NAGRYWANIE: '),
                    Text(
                      _formatTime(_recordingTime),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Strona',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isRecording
                            ? null
                            : () {
                                setState(() {
                                  _selectedSide = 'left';
                                });
                              },
                        style: OutlinedButton.styleFrom(
                          backgroundColor:
                              _selectedSide == 'left' ? const Color(0xFF3B82F6) : Colors.white,
                          foregroundColor:
                              _selectedSide == 'left' ? Colors.white : const Color(0xFF111827),
                        ),
                        child: const Text('Lewa'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isRecording
                            ? null
                            : () {
                                setState(() {
                                  _selectedSide = 'right';
                                });
                              },
                        style: OutlinedButton.styleFrom(
                          backgroundColor:
                              _selectedSide == 'right' ? const Color(0xFF3B82F6) : Colors.white,
                          foregroundColor:
                              _selectedSide == 'right' ? Colors.white : const Color(0xFF111827),
                        ),
                        child: const Text('Prawa'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFDBEAFE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'Aktualna konfiguracja:',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_selectedMovement?.name ?? ''} - ${_selectedSide == 'left' ? 'Lewa' : 'Prawa'}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1D4ED8),
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

  Widget _buildMeasurementsCard(BuildContext context) {
    final reversed = _measurements.reversed.toList();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Ostatnie pomiary',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 320,
              child: ListView.builder(
                itemCount: reversed.length,
                itemBuilder: (context, index) {
                  final m = reversed[index];
                  final side = m.side == 'left' ? 'Lewa' : 'Prawa';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${m.movement} - $side',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Czas trwania: ${m.duration.toStringAsFixed(2)}s',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _confirmDeleteMeasurement(m),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFB91C1C),
                          ),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Usuń'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (_measurements.length > 5) ...[
              const SizedBox(height: 4),
              Text(
                'Przewiń w dół, aby zobaczyć więcej (${_measurements.length} pomiarów)',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _confirmDeleteAll,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.delete_forever),
              label: const Text('Usuń wszystkie pomiary'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _exportFile,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.download),
              label: const Text('Eksportuj plik'),
            ),
          ],
        ),
      ),
    );
  }
}