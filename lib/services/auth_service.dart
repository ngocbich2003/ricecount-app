import 'package:flutter/foundation.dart';
import '../utils/database_helper.dart';

class AuthService extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;
  
  String? _userId;
  String? _username;
  bool _isLoggedIn = false;

  String? get userId => _userId;
  String? get username => _username;
  bool get isLoggedIn => _isLoggedIn;

  Future<bool> register(String username, String password) async {
    try {
      final success = await _db.registerUser(username, password);
      if (success) {
        await login(username, password);
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('Registration error: $e');
      }
      return false;
    }
  }

  Future<bool> login(String username, String password) async {
    try {
      final user = await _db.loginUser(username, password);
      if (user != null) {
        _userId = user['id'].toString();
        _username = user['username'];
        _isLoggedIn = true;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('Login error: $e');
      }
      return false;
    }
  }

  void logout() {
    _userId = null;
    _username = null;
    _isLoggedIn = false;
    notifyListeners();
  }

  // Check if user is already logged in (if you want to implement persistence)
  Future<bool> checkLoginStatus() async {
    // We don't have persistence in this simple implementation
    // but you could add it using shared preferences
    return _isLoggedIn;
  }
}