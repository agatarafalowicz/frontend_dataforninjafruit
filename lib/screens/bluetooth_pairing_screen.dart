import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_dataforninjafruit/models/metawear_device.dart';
import 'package:frontend_dataforninjafruit/services/metawear_service.dart';
import 'package:frontend_dataforninjafruit/services/metawear_protocol.dart';
import 'package:frontend_dataforninjafruit/theme/app_theme.dart';

class BluetoothPairingScreen extends StatefulWidget {
  final MetaWearService? service;

  const BluetoothPairingScreen({super.key, this.service});

  @override
  State<BluetoothPairingScreen> createState() => _BluetoothPairingScreenState();
}

class _BluetoothPairingScreenState extends State<BluetoothPairingScreen> {
  late final MetaWearService _service;
  final List<MetawearDevice> _devices = [];
  bool _isScanning = false;
  StreamSubscription? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? MetaWearService();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissionsAndScan();
    });
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _requestPermissionsAndScan() async {
    if (Platform.isAndroid) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
    }
    _startScan();
  }

  Future<void> _startScan() async {
    if (_isScanning) return;
    setState(() {
      _devices.clear();
      _isScanning = true;
    });

    try {
      await FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          if (!mounted) return;
          final name = r.device.platformName;
          final uuids = r.advertisementData.serviceUuids
              .map((u) => u.toString().toLowerCase())
              .toList();
          final isMetaWear =
              name.toLowerCase().contains('metawear') ||
              name.toLowerCase().contains('metamotion') ||
              uuids.contains(kServiceUuid.toLowerCase());
          if (isMetaWear &&
              !_devices.any((d) => d.id == r.device.remoteId.str)) {
            setState(() {
              _devices.add(
                MetawearDevice(
                  id: r.device.remoteId.str,
                  name: name.isEmpty
                      ? 'MetaWear (${r.device.remoteId.str})'
                      : name,
                  rssi: r.rssi,
                ),
              );
            });
          }
        }
      });

      await FlutterBluePlus.startScan(
        withServices: [Guid(kServiceUuid)],
        timeout: const Duration(seconds: 12),
      );

      await Future.delayed(const Duration(seconds: 13));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Błąd skanowania: $e')));
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _connect(MetawearDevice device) async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Łączenie z MetaWear...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await _service.connect(device.id);
      await _service.initializeBoard();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pairedDeviceName', device.name);
      await prefs.setString('pairedDeviceId', device.id);
      await prefs.setString('pairedDeviceType', 'MetaMotion');

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(_service);
      } else {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/home', (_) => false, arguments: _service);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Błąd połączenia: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wybierz MetaWear'),
        actions: [
          if (_isScanning)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Skanuj ponownie',
              onPressed: _startScan,
            ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.pageGradient),
        child: Column(
          children: [
            // // ── Folder zapisu ──────────────────────────────────────────────
            // Padding(
            //   padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            //   child: InkWell(
            //     onTap: _pickFolder,
            //     borderRadius: BorderRadius.circular(12),
            //     child: Container(
            //       padding: const EdgeInsets.symmetric(
            //         horizontal: 14,
            //         vertical: 12,
            //       ),
            //       decoration: BoxDecoration(
            //         color: Colors.white,
            //         borderRadius: BorderRadius.circular(12),
            //         border: Border.all(color: const Color(0xFFE5E7EB)),
            //         boxShadow: [
            //           BoxShadow(
            //             color: Colors.black.withValues(alpha: .04),
            //             // color: Colors.black.withOpacity(0.04),
            //             blurRadius: 6,
            //             offset: const Offset(0, 2),
            //           ),
            //         ],
            //       ),
            //       child: Row(
            //         children: [
            //           const Icon(Icons.folder_open, color: Colors.amber),
            //           const SizedBox(width: 12),
            //           Expanded(
            //             child: Column(
            //               crossAxisAlignment: CrossAxisAlignment.start,
            //               children: [
            //                 const Text(
            //                   'Folder zapisu CSV',
            //                   style: TextStyle(
            //                     fontSize: 11,
            //                     color: Color(0xFF6B7280),
            //                   ),
            //                 ),
            //                 const SizedBox(height: 2),
            //                 Text(
            //                   _saveDir.isEmpty
            //                       ? 'Dotknij aby wybrać...'
            //                       : _saveDir,
            //                   style: TextStyle(
            //                     fontSize: 12,
            //                     fontFamily: 'monospace',
            //                     color: _saveDir.isEmpty
            //                         ? const Color(0xFF9CA3AF)
            //                         : const Color(0xFF1D4ED8),
            //                   ),
            //                   overflow: TextOverflow.ellipsis,
            //                 ),
            //               ],
            //             ),
            //           ),
            //           const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
            //         ],
            //       ),
            //     ),
            //   ),
            // ),

            // const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Wybierz urządzenie z listy',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 4),

            // ── Lista urządzeń ─────────────────────────────────────────────
            Expanded(
              child: _devices.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isScanning
                                ? Icons.bluetooth_searching
                                : Icons.bluetooth_disabled,
                            size: 64,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _isScanning
                                ? 'Skanowanie...'
                                : 'Nie znaleziono urządzeń',
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                          if (!_isScanning) ...[
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _startScan,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Skanuj ponownie'),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _devices.length,
                      itemBuilder: (context, index) {
                        final device = _devices[index];
                        return Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          margin: const EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 4,
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: const CircleAvatar(
                              backgroundColor: AppColors.primarySoft,
                              child: Icon(
                                Icons.bluetooth,
                                color: AppColors.primary,
                              ),
                            ),
                            title: Text(
                              device.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('MAC: ${device.id}'),
                                Text(
                                  'Sygnał: ${device.rssi} dBm',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                            trailing: ElevatedButton(
                              onPressed: () => _connect(device),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(80, 36),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text('Połącz'),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
