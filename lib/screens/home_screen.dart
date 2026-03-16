import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:frontend_dataforninjafruit/models/user.dart';
import 'package:frontend_dataforninjafruit/screens/bluetooth_pairing_screen.dart';
import 'package:frontend_dataforninjafruit/theme/app_theme.dart';
import '../services/metawear_service.dart';
import '../services/metawear_protocol.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Modele lokalne
// ─────────────────────────────────────────────────────────────────────────────

class Movement {
  final int id;
  final String name;
  final IconData icon;
  const Movement({required this.id, required this.name, required this.icon});
}

class Measurement {
  final String id;
  final String movement;
  final String side;
  final double duration;
  final int timestamp;
  final List<String> csvPaths;

  Measurement({
    required this.id,
    required this.movement,
    required this.side,
    required this.duration,
    required this.timestamp,
    this.csvPaths = const [],
  });

  factory Measurement.fromJson(Map<String, dynamic> json) => Measurement(
    id: json['id'] as String,
    movement: json['movement'] as String,
    side: json['side'] as String,
    duration: (json['duration'] as num).toDouble(),
    timestamp: json['timestamp'] as int,
    csvPaths:
        (json['csvPaths'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        [],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'movement': movement,
    'side': side,
    'duration': duration,
    'timestamp': timestamp,
    'csvPaths': csvPaths,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// HomeScreen
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ── Serwis BLE ─────────────────────────────────────────────────────────────
  late MetaWearService _bleService;
  StreamSubscription? _accSub;
  StreamSubscription? _gyroSub;
  StreamSubscription<bool>? _connectionSub;

  // ── Dane z sensorów ────────────────────────────────────────────────────────
  SensorSample? _acc;
  SensorSample? _gyro;

  // ── Lista ruchów ──────────────────────────────────────────────────────────
  final List<Movement> _movements = const [
    Movement(id: 1, name: 'Fala', icon: Icons.waves),
    Movement(id: 2, name: 'Machanie', icon: Icons.pan_tool_alt),
    Movement(
      id: 3,
      name: 'Okrąg (zgodnie ze wskazówkami zegara)',
      icon: Icons.rotate_right,
    ),
    Movement(
      id: 4,
      name: 'Okrąg (przeciwnie do wskazówek zegara)',
      icon: Icons.rotate_left,
    ),
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

  // ── Info o urządzeniu ──────────────────────────────────────────────────────
  String _pairedDeviceName = '';
  String _pairedDeviceId = '';

  // ── Folder zapisu ─────────────────────────────────────────────────────────
  String _saveDir = '';

  @override
  void initState() {
    super.initState();
    _selectedMovement = _movements.first;
    _bleService = MetaWearService();
    _subscribeSensors();
    _subscribeConnectionState();
    _loadSaveDir();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        _applyPairingResult(args);
      } else if (args is MetaWearService && !identical(args, _bleService)) {
        _attachBleService(args);
      }

      await _clearStoredPairedDevice();

      if (!mounted) return;
      if (!_bleService.isConnected) {
        await _openPairing();
      }
    });

    _loadCurrentUser();
    _loadMeasurements();
  }

  void _attachBleService(MetaWearService service) {
    _accSub?.cancel();
    _gyroSub?.cancel();
    _connectionSub?.cancel();
    _bleService = service;
    _subscribeSensors();
    _subscribeConnectionState();
    _loadSaveDir();
  }

  void _subscribeSensors() {
    _accSub = _bleService.accStream.listen((s) => setState(() => _acc = s));
    _gyroSub = _bleService.gyroStream.listen((s) => setState(() => _gyro = s));
  }

  void _subscribeConnectionState() {
    _connectionSub = _bleService.connectionStateStream.listen((connected) {
      if (!mounted) return;
      setState(() {
        if (!connected && _isRecording) {
          _isRecording = false;
          _recordingTime = 0;
          _timer?.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _accSub?.cancel();
    _gyroSub?.cancel();
    _connectionSub?.cancel();
    if (_isRecording) _bleService.stopIMU();
    super.dispose();
  }

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<void> _loadSaveDir() async {
    final dir = await _bleService.getSaveDir();
    if (mounted) setState(() => _saveDir = dir);
  }

  Future<void> _pickFolder() async {
    if (Platform.isAndroid) {
      await Permission.manageExternalStorage.request();
    }
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Wybierz folder zapisu CSV',
    );
    if (path != null) {
      await _bleService.setSaveDir(path);
      if (mounted) setState(() => _saveDir = path);
    }
  }

  Future<void> _openPairing() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => BluetoothPairingScreen(service: _bleService),
      ),
    );

    if (result == null) {
      return;
    }

    _applyPairingResult(result);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Parowanie zakończone.')));
    }
  }

  void _applyPairingResult(Map<String, dynamic> result) {
    final service = result['service'];
    final deviceName = (result['deviceName'] as String?) ?? '';
    final deviceId = (result['deviceId'] as String?) ?? '';

    if (service is MetaWearService && !identical(service, _bleService)) {
      _attachBleService(service);
    }

    if (mounted) {
      setState(() {
        _pairedDeviceName = deviceName;
        _pairedDeviceId = deviceId;
      });
    } else {
      _pairedDeviceName = deviceName;
      _pairedDeviceId = deviceId;
    }
  }

  Future<void> _clearStoredPairedDevice() async {
    final prefs = await _prefs();
    await prefs.remove('pairedDeviceName');
    await prefs.remove('pairedDeviceId');
    await prefs.remove('pairedDeviceType');
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await _prefs();
    final value = prefs.getString('currentUser');
    if (value == null || value.isEmpty) return;
    try {
      setState(() => _currentUser = AppUser.fromJsonString(value));
    } catch (_) {}
  }

  Future<void> _loadMeasurements() async {
    final prefs = await _prefs();
    final value = prefs.getString('measurements');
    if (value == null || value.isEmpty) return;
    try {
      final parsed = jsonDecode(value);
      if (parsed is List) {
        setState(() {
          _measurements = parsed
              .whereType<Map<String, dynamic>>()
              .map((e) => Measurement.fromJson(e))
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _saveMeasurements() async {
    final prefs = await _prefs();
    await prefs.setString(
      'measurements',
      jsonEncode(_measurements.map((e) => e.toJson()).toList()),
    );
  }

  String _formatTime(double seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds.truncate() % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Iterable<String> _allRecordedCsvPaths() {
    return _measurements
        .expand((m) => m.csvPaths)
        .where((p) => p.trim().isNotEmpty)
        .toSet();
  }

  Future<({int deleted, int missing, int failed})> _deleteCsvFiles(
    Iterable<String> paths,
  ) async {
    var deleted = 0;
    var missing = 0;
    var failed = 0;

    for (final path in paths.toSet()) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          deleted++;
        } else {
          missing++;
        }
      } catch (_) {
        failed++;
      }
    }

    return (deleted: deleted, missing: missing, failed: failed);
  }

  String _fileNameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.split('/').last;
  }

  // ── Start / Stop nagrywania ────────────────────────────────────────────────
  Future<void> _toggleRecording() async {
    if (_isRecording) {
      // STOP
      setState(() => _isRecording = false);
      _timer?.cancel();

      List<String> paths = [];
      if (_bleService.isConnected) {
        paths = await _bleService.stopIMU();
      }

      final movement = _selectedMovement?.name ?? 'Nieznany';
      final side = _selectedSide == 'left' ? 'Lewa' : 'Prawa';

      // Zmień nazwy plików, żeby zawierały nazwę ruchu i stronę
      final renamedPaths = <String>[];
      for (final p in paths) {
        try {
          final file = File(p);
          final dir = file.parent.path;
          final oldName = file.uri.pathSegments.last;
          // Wstaw nazwę ruchu przed rozszerzeniem
          final movementSlug = movement
              .replaceAll(' ', '_')
              .replaceAll('(', '')
              .replaceAll(')', '')
              .replaceAll('ą', 'a')
              .replaceAll('ę', 'e')
              .replaceAll('ó', 'o')
              .replaceAll('ś', 's')
              .replaceAll('ł', 'l')
              .replaceAll('ż', 'z')
              .replaceAll('ź', 'z')
              .replaceAll('ć', 'c')
              .replaceAll('ń', 'n')
              .replaceAll('ź', 'z');
          final newName = oldName.replaceFirst(
            '.csv',
            '_${movementSlug}_$side.csv',
          );
          final newPath = '$dir/$newName';
          await file.rename(newPath);
          renamedPaths.add(newPath);
        } catch (_) {
          renamedPaths.add(p);
        }
      }

      final measurement = Measurement(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        movement: movement,
        side: _selectedSide,
        duration: _recordingTime,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        csvPaths: renamedPaths,
      );
      setState(() {
        _measurements = [..._measurements, measurement];
        _recordingTime = 0;
      });
      _saveMeasurements();

      if (renamedPaths.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Zapisano ${renamedPaths.length} plik(ów) CSV'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } else {
      // START
      if (!_bleService.isConnected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Najpierw połącz urządzenie MetaWear.')),
          );
        }
        return;
      }

      try {
        await _bleService.startIMU();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Błąd IMU: $e')));
        }
        return;
      }
      setState(() {
        _recordingTime = 0;
        _isRecording = true;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
        setState(() {
          _recordingTime = double.parse(
            (_recordingTime + 0.01).toStringAsFixed(2),
          );
        });
      });
    }
  }

  // ── Rozłącz / Podłącz ponownie ────────────────────────────────────────────
  Future<void> _reconnect() async {
    if (_bleService.isConnected) {
      await _bleService.disconnect();
      if (mounted) {
        setState(() {
          _pairedDeviceId = '';
          _pairedDeviceName = '';
        });
      }
      return;
    }

    if (_pairedDeviceId.isEmpty) {
      await _openPairing();
      return;
    }

    try {
      await _bleService.connect(_pairedDeviceId);
      await _bleService.initializeBoard();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ponownie połączono!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Błąd połączenia: $e')));
      }
    }
  }

  Future<void> _confirmDeleteMeasurement(Measurement m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Czy na pewno usunąć?'),
        content: const Text('Ta operacja jest nieodwracalna.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Nie'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Tak'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final deleteResult = await _deleteCsvFiles(m.csvPaths);

      setState(
        () => _measurements = _measurements.where((x) => x.id != m.id).toList(),
      );
      _saveMeasurements();

      if (mounted) {
        final message =
            'Usunięto pomiar i ${deleteResult.deleted} plik(ów) CSV'
            '${deleteResult.missing > 0 ? ', brakujących: ${deleteResult.missing}' : ''}'
            '${deleteResult.failed > 0 ? ', błędy: ${deleteResult.failed}' : ''}.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor:
                deleteResult.failed > 0 ? AppColors.warning : AppColors.success,
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Usuń wszystkie pomiary?'),
        content: const Text('Ta operacja jest nieodwracalna.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Nie'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Tak'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final deleteResult = await _deleteCsvFiles(_allRecordedCsvPaths());

      setState(() => _measurements = []);
      final prefs = await _prefs();
      await prefs.remove('measurements');

      if (mounted) {
        final message =
            'Usunięto pomiary i ${deleteResult.deleted} plik(ów) CSV'
            '${deleteResult.missing > 0 ? ', brakujących: ${deleteResult.missing}' : ''}'
            '${deleteResult.failed > 0 ? ', błędy: ${deleteResult.failed}' : ''}.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor:
                deleteResult.failed > 0 ? AppColors.warning : AppColors.success,
          ),
        );
      }
    }
  }

  Future<void> _exportFile() async {
    if (_measurements.isEmpty) return;

    final allPaths = _allRecordedCsvPaths().toList();
    if (allPaths.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Brak zapisanych plików CSV do eksportu.')),
        );
      }
      return;
    }

    final existingFiles = <File>[];
    for (final path in allPaths) {
      final f = File(path);
      if (await f.exists()) {
        existingFiles.add(f);
      }
    }

    if (existingFiles.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nie znaleziono istniejących plików CSV.')),
        );
      }
      return;
    }

    final archive = Archive();
    final usedNames = <String, int>{};

    for (final file in existingFiles) {
      final bytes = await file.readAsBytes();
      final baseName = _fileNameFromPath(file.path);
      final count = usedNames.update(baseName, (v) => v + 1, ifAbsent: () => 1);

      var entryName = baseName;
      if (count > 1) {
        final dot = baseName.lastIndexOf('.');
        if (dot > 0) {
          entryName =
              '${baseName.substring(0, dot)}_$count${baseName.substring(dot)}';
        } else {
          entryName = '${baseName}_$count';
        }
      }

      archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
    }

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nie udało się utworzyć pliku ZIP.')),
        );
      }
      return;
    }

    final dirPath = _saveDir.isNotEmpty
        ? _saveDir
        : await _bleService.getSaveDir();
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final fileName = 'pomiary_${DateTime.now().millisecondsSinceEpoch}.zip';
    final exportPath = '${dir.path}${Platform.pathSeparator}$fileName';
    final zipFile = File(exportPath);
    await zipFile.writeAsBytes(zipBytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(files: [XFile(zipFile.path, mimeType: 'application/zip')]),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Wyeksportowano ZIP (${existingFiles.length} plików): $exportPath'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _logout() async {
    final prefs = await _prefs();
    await prefs.remove('currentUser');
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.pageGradient),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeaderCard(),
                      const SizedBox(height: 12),
                      _buildSaveDirCard(),
                      const SizedBox(height: 12),
                      _buildSensorCard(),
                      const SizedBox(height: 12),
                      _buildMovementCard(),
                      const SizedBox(height: 12),
                      _buildControlCard(),
                      if (_measurements.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _buildMeasurementsCard(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeaderCard() {
    final name = _currentUser?.name.isNotEmpty == true
        ? _currentUser!.name
        : _currentUser?.email ?? '';
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Zalogowany jako',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
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
                ),
                OutlinedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Wyloguj'),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                Icon(
                  _bleService.isConnected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  size: 20,
                  color: _bleService.isConnected
                      ? AppColors.primary
                      : AppColors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _pairedDeviceName.isEmpty
                            ? 'Brak urządzenia'
                            : _pairedDeviceName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (_pairedDeviceId.isNotEmpty)
                        Text(
                          'MAC: $_pairedDeviceId',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isRecording ? null : _reconnect,
                  icon: Icon(
                    _bleService.isConnected
                        ? Icons.bluetooth_disabled
                        : Icons.bluetooth_searching,
                    size: 16,
                  ),
                  label: Text(_bleService.isConnected ? 'Rozłącz' : 'Połącz'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _bleService.isConnected
                        ? AppColors.danger
                        : AppColors.primary,
                    minimumSize: const Size(90, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Folder zapisu ──────────────────────────────────────────────────────────
  Widget _buildSaveDirCard() {
    return InkWell(
      onTap: _pickFolder,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.folder_open, color: AppColors.warning),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Folder zapisu CSV',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _saveDir.isEmpty ? 'Dotknij aby wybrać...' : _saveDir,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: _saveDir.isEmpty
                            ? AppColors.textSubtle
                            : AppColors.primaryText,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSubtle),
            ],
          ),
        ),
      ),
    );
  }

  // ── Karta sensorów na żywo ─────────────────────────────────────────────────
  Widget _buildSensorCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.sensors,
                  size: 18,
                  color: _isRecording ? AppColors.danger : AppColors.textMuted,
                ),
                const SizedBox(width: 8),
                Text(
                  _isRecording ? '🔴 Dane na żywo' : 'Dane sensorów',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _isRecording
                        ? AppColors.danger
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _SensorTile('ACC [g]', _acc, AppColors.sensorAcc),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SensorTile('GYRO [°/s]', _gyro, AppColors.sensorGyro),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Wybór ruchu ───────────────────────────────────────────────────────────
  Widget _buildMovementCard() {
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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
              itemBuilder: (_, index) {
                final mv = _movements[index];
                final selected = _selectedMovement?.id == mv.id;
                return InkWell(
                  onTap: _isRecording
                      ? null
                      : () => setState(() => _selectedMovement = mv),
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primarySoft
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? AppColors.primary : AppColors.border,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: FittedBox(
                            child: Icon(
                              mv.icon,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          mv.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
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

  // ── Kontrolki nagrywania ──────────────────────────────────────────────────
  Widget _buildControlCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Wybrany ruch + strona info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text(
                    'Aktualna konfiguracja:',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_selectedMovement?.name ?? ''} — ${_selectedSide == 'left' ? 'Lewa' : 'Prawa'}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Strona
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isRecording
                        ? null
                        : () => setState(() => _selectedSide = 'left'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: _selectedSide == 'left'
                          ? AppColors.primary
                          : AppColors.surface,
                      foregroundColor: _selectedSide == 'left'
                          ? Colors.white
                          : AppColors.textPrimary,
                    ),
                    child: const Text('Lewa'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isRecording
                        ? null
                        : () => setState(() => _selectedSide = 'right'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: _selectedSide == 'right'
                          ? AppColors.primary
                          : AppColors.surface,
                      foregroundColor: _selectedSide == 'right'
                          ? Colors.white
                          : AppColors.textPrimary,
                    ),
                    child: const Text('Prawa'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Start / Stop
            ElevatedButton.icon(
              onPressed: (_isRecording || _bleService.isConnected)
                  ? _toggleRecording
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording
                    ? AppColors.danger
                    : AppColors.success,
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: Icon(_isRecording ? Icons.stop : Icons.play_arrow),
              label: Text(_isRecording ? 'Zakończ ruch' : 'Rozpocznij ruch'),
            ),

            if (_isRecording) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('🔴 NAGRYWANIE: '),
                    Text(
                      _formatTime(_recordingTime),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Lista pomiarów ─────────────────────────────────────────────────────────
  Widget _buildMeasurementsCard() {
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 320,
              child: ListView.builder(
                itemCount: reversed.length,
                itemBuilder: (_, index) {
                  final m = reversed[index];
                  final side = m.side == 'left' ? 'Lewa' : 'Prawa';
                  final date = DateTime.fromMillisecondsSinceEpoch(
                    m.timestamp,
                  ).toLocal();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${m.movement} — $side',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Czas: ${m.duration.toStringAsFixed(2)}s  •  $date',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              if (m.csvPaths.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '💾 ${m.csvPaths.map((p) => p.split('/').last).join('\n💾 ')}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.primaryText,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _confirmDeleteMeasurement(m),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.dangerText,
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
                'Przewiń, aby zobaczyć więcej (${_measurements.length} pomiarów)',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _confirmDeleteAll,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
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
              label: const Text('Eksportuj ZIP (CSV)'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget do wyświetlania danych sensora
// ─────────────────────────────────────────────────────────────────────────────

class _SensorTile extends StatelessWidget {
  final String label;
  final SensorSample? data;
  final Color color;
  const _SensorTile(this.label, this.data, this.color);

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: data != null ? 0.08 : 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: data != null ? color : AppColors.border,
          width: data != null ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          if (data == null)
            Text(
              '— — —',
              style: TextStyle(color: AppColors.textSubtle, fontSize: 12),
            )
          else ...[
            _axisRow('X', data!.x, color),
            _axisRow('Y', data!.y, color),
            _axisRow('Z', data!.z, color),
          ],
        ],
      ),
    );
  }

  Widget _axisRow(String axis, double val, Color c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Text(
            '$axis ',
            style: TextStyle(
              color: c,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Text(
              val.toStringAsFixed(3),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

