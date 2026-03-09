import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/metawear_device.dart';
import '../services/metawear_service.dart';

class BluetoothPairingScreen extends StatefulWidget {
  const BluetoothPairingScreen({super.key});

  @override
  State<BluetoothPairingScreen> createState() => _BluetoothPairingScreenState();
}

class _BluetoothPairingScreenState extends State<BluetoothPairingScreen> {
  final MetawearService _service = MetawearService();
  final List<MetawearDevice> _devices = [];
  bool _isScanning = false;
  StreamSubscription? _scanSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScan();
    });
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _service.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _devices.clear();
      _isScanning = true;
    });

    try {
      _scanSubscription?.cancel();
      _scanSubscription = _service.startScan().listen(
        (device) {
          if (!mounted) return;
          if (!_devices.any((d) => d.id == device.id)) {
            setState(() {
              _devices.add(device);
            });
          }
        },
        onError: (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Błąd skanowania: $e')),
          );
          setState(() => _isScanning = false);
        },
      );
      
      // Auto stop scan after some time
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted) setState(() => _isScanning = false);
      });
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd uprawnień lub Bluetooth: $e')),
        );
        setState(() => _isScanning = false);
      }
    }
  }

  Future<void> _connect(MetawearDevice device) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Łączenie z urządzeniem MetaWear...'),
                ],
              ),
            ),
          ),
        ),
      );

      await _service.connect(device.id);
      
      // Get the real model name from the board
      final modelName = await _service.getModel(device.id);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pairedDeviceName', device.name);
      await prefs.setString('pairedDeviceId', device.id);
      await prefs.setString('pairedDeviceType', modelName);

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // Close loading dialog
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Połączono z $modelName!')),
      );

      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd połączenia: $e')),
        );
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
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _startScan,
            ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE0E7FF), Color(0xFFEDE9FE)],
          ),
        ),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Wyszukiwanie czujników MetaMotion...',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF4B5563)),
              ),
            ),
            Expanded(
              child: _devices.isEmpty && !_isScanning
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.bluetooth_searching, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text('Nie znaleziono urządzeń w pobliżu'),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _startScan,
                            child: const Text('Skanuj ponownie'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _devices.length,
                      itemBuilder: (context, index) {
                        final device = _devices[index];
                        return Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xFFDBEAFE),
                              child: Icon(Icons.bluetooth, color: Color(0xFF3B82F6)),
                            ),
                            title: Text(
                              device.name,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text('MAC: ${device.id}'),
                            trailing: const Icon(Icons.link),
                            onTap: () => _connect(device),
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
