import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_dataforninjafruit/models/user.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final GlobalKey<FormState> _loginFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _registerFormKey = GlobalKey<FormState>();
  final TextEditingController _loginEmailCtrl = TextEditingController();
  final TextEditingController _loginPasswordCtrl = TextEditingController();
  final TextEditingController _registerNameCtrl = TextEditingController();
  final TextEditingController _registerEmailCtrl = TextEditingController();
  final TextEditingController _registerPasswordCtrl = TextEditingController();
  String _error = '';
  bool _obscureLogin = true;
  bool _obscureRegister = true;
  late final AppUser _mockUser;

  @override
  void initState() {
    super.initState();
    _mockUser = AppUser(
      id: 1,
      name: 'Test Test',
      email: 'test@t.pl',
      password: 'password',
    );
    _checkCurrentUser();
  }

  @override
  void dispose() {
    _loginEmailCtrl.dispose();
    _loginPasswordCtrl.dispose();
    _registerNameCtrl.dispose();
    _registerEmailCtrl.dispose();
    _registerPasswordCtrl.dispose();
    super.dispose();
  }

  Future<SharedPreferences> _prefs() {
    return SharedPreferences.getInstance();
  }

  Future<void> _checkCurrentUser() async {
    final prefs = await _prefs();
    final current = prefs.getString('currentUser');
    if (!mounted) return;
    if (current != null && current.isNotEmpty) {
      Navigator.of(context).pushNamedAndRemoveUntil('/pairing', (route) => false);
    }
  }

  Future<List<AppUser>> _loadUsers() async {
    final prefs = await _prefs();
    final value = prefs.getString('users');
    if (value == null || value.isEmpty) {
      return [];
    }
    try {
      final dynamic parsed = jsonDecode(value);
      if (parsed is List) {
        return parsed
            .whereType<Map<String, dynamic>>()
            .map((e) => AppUser.fromJson(e))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveUsers(List<AppUser> users) async {
    final prefs = await _prefs();
    final data = users.map((e) => e.toJson()).toList();
    await prefs.setString('users', jsonEncode(data));
  }

  Future<void> _setCurrentUser(AppUser user) async {
    final prefs = await _prefs();
    await prefs.setString('currentUser', user.toJsonString());
  }

  void _setError(String value) {
    setState(() {
      _error = value;
    });
  }

  Future<void> _handleLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;
    _setError('');
    final email = _loginEmailCtrl.text.trim();
    final password = _loginPasswordCtrl.text.trim();
    if (email == _mockUser.email && password == _mockUser.password) {
      await _setCurrentUser(_mockUser);
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/pairing', (route) => false);
      return;
    }
    final users = await _loadUsers();
    final user = users.where((u) => u.email == email && u.password == password).toList();
    if (user.isNotEmpty) {
      await _setCurrentUser(user.first);
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/pairing', (route) => false);
    } else {
      _setError('Nieprawidłowy email lub hasło');
    }
  }

  Future<void> _handleRegister() async {
    if (!_registerFormKey.currentState!.validate()) return;
    _setError('');
    final name = _registerNameCtrl.text.trim();
    final email = _registerEmailCtrl.text.trim();
    final password = _registerPasswordCtrl.text.trim();
    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      _setError('Wszystkie pola są wymagane');
      return;
    }
    final users = await _loadUsers();
    final exists = users.any((u) => u.email == email);
    if (exists) {
      _setError('Użytkownik z tym emailem już istnieje');
      return;
    }
    final newUser = AppUser(
      id: DateTime.now().millisecondsSinceEpoch,
      name: name,
      email: email,
      password: password,
    );
    final updated = [...users, newUser];
    await _saveUsers(updated);
    await _setCurrentUser(newUser);
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/pairing', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final padding = media.padding;
    final safeHeight = media.size.height - padding.top - padding.bottom;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Color(0xFFEFF6FF),
              Color(0xFFE0E7FF),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 448,
                  minHeight: safeHeight.clamp(0, 900).toDouble(),
                ),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: DefaultTabController(
                      length: 2,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),
                          Text(
                            'MetaMotion Trening',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Zaloguj się lub zarejestruj, aby kontynuować',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: const Color(0xFF6B7280),
                                ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const TabBar(
                              indicatorSize: TabBarIndicatorSize.tab,
                              indicator: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.all(Radius.circular(999)),
                              ),
                              labelColor: Colors.black,
                              unselectedLabelColor: Color(0xFF6B7280),
                              tabs: [
                                Tab(text: 'Logowanie'),
                                Tab(text: 'Rejestracja'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_error.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                _error,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          SizedBox(
                            height: 260,
                            child: TabBarView(
                              children: [
                                _buildLoginTab(context),
                                _buildRegisterTab(context),
                              ],
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildLoginTab(BuildContext context) {
    return Form(
      key: _loginFormKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _loginEmailCtrl,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'twoj@email.com',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: (value) {
                final v = (value ?? '').trim();
                if (v.isEmpty) return 'Podaj email';
                final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                if (!regex.hasMatch(v)) return 'Niepoprawny email';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _loginPasswordCtrl,
              decoration: InputDecoration(
                labelText: 'Hasło',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      _obscureLogin = !_obscureLogin;
                    });
                  },
                  icon: Icon(_obscureLogin ? Icons.visibility : Icons.visibility_off),
                ),
              ),
              obscureText: _obscureLogin,
              textInputAction: TextInputAction.done,
              validator: (value) {
                final v = (value ?? '').trim();
                if (v.isEmpty) return 'Podaj hasło';
                if (v.length < 6) return 'Minimum 6 znaków';
                return null;
              },
              onFieldSubmitted: (_) => _handleLogin(),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFDBEAFE),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dane testowe:',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1D4ED8),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Email: test@t.pl',
                    style: TextStyle(fontSize: 11, color: Color(0xFF1D4ED8)),
                  ),
                  Text(
                    'Hasło: password',
                    style: TextStyle(fontSize: 11, color: Color(0xFF1D4ED8)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _handleLogin,
              child: const Text('Zaloguj się'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegisterTab(BuildContext context) {
    return Form(
      key: _registerFormKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _registerNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Imię i nazwisko',
                hintText: 'Jan Kowalski',
                prefixIcon: Icon(Icons.person_outline),
              ),
              textInputAction: TextInputAction.next,
              validator: (value) {
                final v = (value ?? '').trim();
                if (v.isEmpty) return 'Podaj imię i nazwisko';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _registerEmailCtrl,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'twoj@email.com',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: (value) {
                final v = (value ?? '').trim();
                if (v.isEmpty) return 'Podaj email';
                final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                if (!regex.hasMatch(v)) return 'Niepoprawny email';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _registerPasswordCtrl,
              decoration: InputDecoration(
                labelText: 'Hasło',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      _obscureRegister = !_obscureRegister;
                    });
                  },
                  icon: Icon(_obscureRegister ? Icons.visibility : Icons.visibility_off),
                ),
              ),
              obscureText: _obscureRegister,
              textInputAction: TextInputAction.done,
              validator: (value) {
                final v = (value ?? '').trim();
                if (v.isEmpty) return 'Podaj hasło';
                if (v.length < 6) return 'Minimum 6 znaków';
                return null;
              },
              onFieldSubmitted: (_) => _handleRegister(),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _handleRegister,
              child: const Text('Zarejestruj się'),
            ),
          ],
        ),
      ),
    );
  }
}
