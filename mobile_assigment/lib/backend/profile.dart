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

/// 统一后端接口（可替换成 Firebase 实现）
abstract class ProfileBackend {
  static ProfileBackend instance = MockProfileBackend();

  /// 当前用户（未登录则为 null）
  User? get currentUser;

  Future<User> signIn(String email, String password);
  Future<User> register({
    required String name,
    required String email,
    required String password,
    String? plateNo,
  });

  Future<void> signOut();
}

/// Mock 版（仅联调 UI）
class MockProfileBackend implements ProfileBackend {
  final Map<String, User> _db = {}; // email -> user
  User? _current;

  @override
  User? get currentUser => _current;

  @override
  Future<User> signIn(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 800));
    final u = _db[email.toLowerCase()];
    if (u == null) throw AuthException('Account not found, please register');
    _current = u; // 设置登录态
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
    _current = user; // 注册成功即登录
    return user;
  }

  @override
  Future<void> signOut() async {
    await Future.delayed(const Duration(milliseconds: 300));
    _current = null;
  }
}
