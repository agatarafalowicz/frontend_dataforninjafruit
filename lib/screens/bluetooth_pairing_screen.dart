import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BluetoothPairingScreen extends StatefulWidget {
  const BluetoothPairingScreen({super.key});

  @override
  State<BluetoothPairingScreen> createState() => _BluetoothPairingScreenState();
}

class _BluetoothPairingScreenState extends State<BluetoothPairingScreen> {
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _isSimulationMode = false;
  String _error = '';
  String _deviceName = '';
  String? _selectedSensor;

  Future<SharedPreferences> _prefs() {
    return SharedPreferences.getInstance();
  }

  Future<void> _handleConnect() async {
    if (_selectedSensor == null || _isConnecting || _isConnected) {
      return;
    }
    setState(() {
      _isConnecting = true;
      _error = '';
    });
    final prefs = await _prefs();
    await prefs.setString('selectedSensor', _selectedSensor!);
    setState(() {
      _isSimulationMode = true;
    });
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() {
      _deviceName = 'MetaMotion ${_selectedSensor!} (Symulacja)';
      _isConnected = true;
      _isConnecting = false;
    });
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Color(0xFFF5F3FF),
              Color(0xFFFCE7F3),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 448),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _isConnected
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFF3B82F6),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isConnected ? Icons.check : Icons.bluetooth,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _isConnected ? 'Połączono pomyślnie!' : 'Parowanie z MetaMotion',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isConnected
                              ? 'Przekierowywanie do aplikacji...'
                              : 'Połącz się z czujnikiem przez Bluetooth',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF6B7280),
                              ),
                        ),
                        const SizedBox(height: 20),
                        if (!_isConnected) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0E7FF),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFF818CF8)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Z jakiego czujnika MetaMotion korzystasz?',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    for (final sensor in ['RL', 'S', 'C'])
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 4),
                                          child: InkWell(
                                            onTap: _isConnecting
                                                ? null
                                                : () {
                                                    setState(() {
                                                      _selectedSensor = sensor;
                                                    });
                                                  },
                                            borderRadius: BorderRadius.circular(12),
                                            child: AnimatedContainer(
                                              duration: const Duration(milliseconds: 150),
                                              padding: const EdgeInsets.symmetric(
                                                vertical: 16,
                                              ),
                                              decoration: BoxDecoration(
                                                color: _selectedSensor == sensor
                                                    ? const Color(0xFFDBEAFE)
                                                    : Colors.white,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: _selectedSensor == sensor
                                                      ? const Color(0xFF3B82F6)
                                                      : const Color(0xFFD1D5DB),
                                                  width: 2,
                                                ),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  sensor,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF374151),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDBEAFE),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFBFDBFE)),
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Upewnij się, że:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text('• MetaMotion jest włączony'),
                                Text('• Urządzenie jest w pobliżu'),
                                Text('• Bluetooth w telefonie jest włączony'),
                              ],
                            ),
                          ),
                          if (_isSimulationMode && !_isConnected && _error.isEmpty) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFFCD34D)),
                              ),
                              child: const Text(
                                'Tryb demonstracyjny: aplikacja działa w trybie symulacji połączenia.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF92400E),
                                ),
                              ),
                            ),
                          ],
                          if (_error.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFFCA5A5)),
                              ),
                              child: Text(
                                _error,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFFB91C1C),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          if (_selectedSensor != null)
                            ElevatedButton.icon(
                              onPressed: _handleConnect,
                              icon: _isConnecting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : const Icon(Icons.bluetooth),
                              label: Text(
                                _isConnecting
                                    ? 'Łączenie...'
                                    : 'Połącz z MetaMotion ${_selectedSensor!}',
                              ),
                            ),
                        ],
                        if (_isConnected && _deviceName.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFF6EE7B7)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  'Połączono z: $_deviceName',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF166534),
                                  ),
                                ),
                                if (_isSimulationMode)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: Text(
                                      '(Tryb symulacji)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFFCA8A04),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


