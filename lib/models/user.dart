import 'dart:convert';

class AppUser {
  final int id;
  final String name;
  final String email;
  final String password;

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.password,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
      password: json['password'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'password': password,
    };
  }

  static AppUser fromJsonString(String value) {
    return AppUser.fromJson(jsonDecode(value) as Map<String, dynamic>);
  }

  String toJsonString() {
    return jsonEncode(toJson());
  }
}


