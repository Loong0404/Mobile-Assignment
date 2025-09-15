class AuthException implements Exception {
  final String message;
  AuthException(this.message);
}

class User {
  final String id;
  final String name;
  final String email;
  final String? plateNo;
  User({
    required this.id,
    required this.name,
    required this.email,
    this.plateNo,
  });
}

/// 你可以后续替换为 Firebase 实现；UI 只依赖这个接口
abstract class ProfileBackend {
  static ProfileBackend instance = MockProfileBackend();

  Future<User> signIn(String email, String password);
  Future<User> register({
    required String name,
    required String email,
    required String password,
    String? plateNo,
  });
}

/// Mock 版：仅用于联调 UI
class MockProfileBackend implements ProfileBackend {
  final Map<String, User> _db = {}; // email -> user

  @override
  Future<User> signIn(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 800));
    final u = _db[email.toLowerCase()];
    if (u == null) throw AuthException('Account not found, please register');
    return u;
  }

  @override
  Future<User> register({
    required String name,
    required String email,
    required String password,
    String? plateNo,
  }) async {
    await Future.delayed(const Duration(milliseconds: 900));
    final key = email.toLowerCase();
    if (_db.containsKey(key)) {
      throw AuthException('Email already registered');
    }
    final user = User(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      email: key,
      plateNo: plateNo,
    );
    _db[key] = user;
    return user;
  }
}
