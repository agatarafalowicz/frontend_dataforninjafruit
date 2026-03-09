// metawear_service.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'metawear_protocol.dart';

class MetaWearService {
  BluetoothDevice?         _device;
  BluetoothCharacteristic? _cmd;
  BluetoothCharacteristic? _notify;
  StreamSubscription?      _notifySub;

  final _accCtrl  = StreamController<SensorSample>.broadcast();
  final _gyroCtrl = StreamController<SensorSample>.broadcast();
  final _logCtrl  = StreamController<String>.broadcast();

  Stream<SensorSample> get accStream  => _accCtrl.stream;
  Stream<SensorSample> get gyroStream => _gyroCtrl.stream;
  Stream<String>       get logStream  => _logCtrl.stream;

  bool get isConnected => _cmd != null;
  bool _running = false;
  bool get isRunning => _running;

  final _accBuf  = <SensorSample>[];
  final _gyroBuf = <SensorSample>[];
  DateTime? _startTime;

  // ── Zapamiętany folder zapisu ───────────────────────────────────────────

  Future<String> getSaveDir() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('save_dir');
    if (saved != null && await Directory(saved).exists()) return saved;
    // Domyślnie Documents
    return (await getApplicationDocumentsDirectory()).path;
  }

  Future<void> setSaveDir(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('save_dir', path);
    _log('📁 Folder zapisu: $path');
  }

  // ── Połączenie ──────────────────────────────────────────────────────────

  Future<void> scanAndConnect() async {
    _log('Skanuję MetaWear...');
    await FlutterBluePlus.stopScan();
    final completer = Completer<BluetoothDevice>();
    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final uuids = r.advertisementData.serviceUuids
            .map((u) => u.toString().toLowerCase()).toList();
        if (r.device.platformName.toLowerCase().contains('metawear') ||
            uuids.contains(kServiceUuid.toLowerCase())) {
          if (!completer.isCompleted) {
            _log('Znaleziono: ${r.device.platformName} [${r.device.remoteId}]');
            completer.complete(r.device);
          }
        }
      }
    });
    await FlutterBluePlus.startScan(
      withServices: [Guid(kServiceUuid)],
      timeout: const Duration(seconds: 10),
    );
    try {
      _device = await completer.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw TimeoutException('Nie znaleziono MetaWear'),
      );
    } finally {
      await sub.cancel();
      await FlutterBluePlus.stopScan();
    }
    await _connectDevice();
  }

  Future<void> connect(String mac) async {
    _log('Łączę z $mac...');
    _device = BluetoothDevice.fromId(mac);
    await _connectDevice();
  }

  Future<void> _connectDevice() async {
    await _device!.connect(license: License.free, timeout: const Duration(seconds: 15));
    _device!.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected) {
        _cmd = null; _notify = null; _running = false;
        _log('Rozłączono.');
      }
    });
    await _device!.discoverServices();
    for (final svc in _device!.servicesList) {
      if (svc.uuid.toString().toLowerCase() != kServiceUuid.toLowerCase()) continue;
      for (final c in svc.characteristics) {
        final u = c.uuid.toString().toLowerCase();
        if (u == kCommandUuid.toLowerCase()) _cmd    = c;
        if (u == kNotifyUuid.toLowerCase())  _notify = c;
      }
    }
    if (_cmd == null) throw Exception('Nie znaleziono MetaWear');
    if (_notify != null) {
      await _notify!.setNotifyValue(true);
      _notifySub = _notify!.lastValueStream.listen(_onNotify);
    }
    _log('Połączono ✓');
  }

  Future<void> disconnect() async {
    if (_running) await stopIMU();
    await _notifySub?.cancel();
    await _device?.disconnect();
  }

  // ── Inicjalizacja board ─────────────────────────────────────────────────

  Future<void> initializeBoard() async {
    _log('Inicjalizuję board...');
    final modules = [0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,
      0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0f,0x10,
      0x11,0x12,0x13,0x14,0x15,0xfe];
    for (final m in modules) {
      await _send([m, 0x80]);
      await Future.delayed(const Duration(milliseconds: 30));
    }
    await Future.delayed(const Duration(milliseconds: 500));
    _log('Board gotowy.');
  }

  // ── Streaming ───────────────────────────────────────────────────────────

  Future<void> startIMU() async {
    if (_running) return;
    _accBuf.clear();
    _gyroBuf.clear();
    _startTime = DateTime.now();
    await _send(accConfig());
    await _send(accSubscribe());
    await _send(accEnable());
    await _send(accStart());
    await _send(gyroConfig());
    await _send(gyroSubscribe());
    await _send(gyroEnable());
    await _send(gyroStart());
    _running = true;
    _log('▶ Streaming start');
  }

  Future<List<String>> stopIMU() async {
    if (!_running) return [];
    await _send(accStop());
    await _send(accDisable());
    await _send(accUnsubscribe());
    await _send(gyroStop());
    await _send(gyroDisable());
    await _send(gyroUnsubscribe());
    _running = false;
    _log('■ Streaming stop — zapisuję CSV...');
    final paths = await _saveCsv();
    for (final p in paths) { _log('💾 $p'); }
    return paths;
  }

  // ── Notyfikacje ─────────────────────────────────────────────────────────

  void _onNotify(List<int> b) {
    final acc = parseAcc(b);
    if (acc != null) { _accCtrl.add(acc); if (_running) _accBuf.add(acc); return; }
    final gyro = parseGyro(b);
    if (gyro != null) { _gyroCtrl.add(gyro); if (_running) _gyroBuf.add(gyro); }
  }

  // ── Zapis CSV ───────────────────────────────────────────────────────────

  Future<List<String>> _saveCsv() async {
    final dirPath = await getSaveDir();
    final dir     = Directory(dirPath);
    if (!await dir.exists()) await dir.create(recursive: true);

    final ts  = _startTime!.toIso8601String().replaceAll(':', '_').replaceAll('.', '_');
    final mac = _device?.remoteId.toString().replaceAll(':', '') ?? 'UNKNOWN';

    String fmt(double v) => v.toStringAsFixed(3);

    // Akcelerometr
    final accPath = '$dirPath/MetaWear_${ts}_${mac}_Accelerometer.csv';
    final accSb   = StringBuffer();
    accSb.writeln('epoch (ms),time (01:00),elapsed (s),x-axis (g),y-axis (g),z-axis (g)');
    final t0a = _accBuf.isNotEmpty ? _accBuf.first.time.millisecondsSinceEpoch : 0;
    for (final s in _accBuf) {
      final el = (s.time.millisecondsSinceEpoch - t0a) / 1000;
      accSb.writeln('${s.time.millisecondsSinceEpoch},${s.time.toIso8601String()},'
          '${el.toStringAsFixed(3)},${fmt(s.x)},${fmt(s.y)},${fmt(s.z)}');
    }
    await File(accPath).writeAsString(accSb.toString());

    // Żyroskop
    final gyroPath = '$dirPath/MetaWear_${ts}_${mac}_Gyroscope.csv';
    final gyroSb   = StringBuffer();
    gyroSb.writeln('epoch (ms),time (01:00),elapsed (s),x-axis (deg/s),y-axis (deg/s),z-axis (deg/s)');
    final t0g = _gyroBuf.isNotEmpty ? _gyroBuf.first.time.millisecondsSinceEpoch : 0;
    for (final s in _gyroBuf) {
      final el = (s.time.millisecondsSinceEpoch - t0g) / 1000;
      gyroSb.writeln('${s.time.millisecondsSinceEpoch},${s.time.toIso8601String()},'
          '${el.toStringAsFixed(3)},${fmt(s.x)},${fmt(s.y)},${fmt(s.z)}');
    }
    await File(gyroPath).writeAsString(gyroSb.toString());

    return [accPath, gyroPath];
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  Future<void> _send(List<int> b) async {
    if (_cmd == null) return;
    await _cmd!.write(b, withoutResponse: true);
    await Future.delayed(const Duration(milliseconds: 30));
  }

  void _log(String msg) => _logCtrl.add(msg);

  void dispose() {
    _accCtrl.close();
    _gyroCtrl.close();
    _logCtrl.close();
  }
}