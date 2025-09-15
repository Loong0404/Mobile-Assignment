// lib/backend/profile.dart
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:cloud_firestore/cloud_firestore.dart' as fs;

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
}

class User {
  final String id; // Firebase UID
  final String name; // 来自 Auth.displayName 或 Firestore
  final String email; // 来自 Auth.email 或 Firestore
  final String? plateNo; // 来自 Firestore
  User({
    required this.id,
    required this.name,
    required this.email,
    this.plateNo,
  });

  User copyWith({String? name, String? email, String? plateNo}) => User(
    id: id,
    name: name ?? this.name,
    email: email ?? this.email,
    plateNo: plateNo ?? this.plateNo,
  );
}

/// 统一后端接口（UI 只依赖这个接口；实现可自由替换）
abstract class ProfileBackend {
  static ProfileBackend instance = MockProfileBackend();

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

/// Mock 版（仅联调 UI；保留，不再默认使用）
class MockProfileBackend implements ProfileBackend {
  final Map<String, User> _db = {}; // email -> user
  User? _current;

  @override
  User? get currentUser => _current;

  @override
  Future<User> signIn(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final u = _db[email.toLowerCase()];
    if (u == null) throw AuthException('Account not found, please register');
    _current = u;
    return u;
  }

  @override
  Future<User> register({
    required String name,
    required String email,
    required String password,
    String? plateNo,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));
    final key = email.toLowerCase();
    if (_db.containsKey(key)) throw AuthException('Email already registered');
    final user = User(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      email: key,
      plateNo: plateNo,
    );
    _db[key] = user;
    _current = user;
    return user;
  }

  @override
  Future<void> signOut() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _current = null;
  }
}

/// =======================
/// Firebase 实现（Auth + Firestore）
/// =======================
class FirebaseProfileBackend implements ProfileBackend {
  final fb.FirebaseAuth _auth = fb.FirebaseAuth.instance;
  final fs.FirebaseFirestore _db = fs.FirebaseFirestore.instance;

  User? _current;
  StreamSubscription<fb.User?>? _authSub;
  StreamSubscription<fs.DocumentSnapshot<Map<String, dynamic>>>? _docSub;

  FirebaseProfileBackend() {
    // 初始映射
    _current = _mapAuth(_auth.currentUser);
    // 监听登录态
    _authSub = _auth.authStateChanges().listen((fb.User? u) {
      _current = _mapAuth(u);
      _attachUserDoc(u);
    });
    // 首次附加
    _attachUserDoc(_auth.currentUser);
  }

  @override
  User? get currentUser => _current;

  // -------- Auth <-> 本地模型 映射 --------
  User? _mapAuth(fb.User? u) {
    if (u == null) return null;
    final email = u.email ?? '';
    final name =
        u.displayName ?? (email.isNotEmpty ? email.split('@').first : 'User');
    return User(id: u.uid, name: name, email: email, plateNo: null);
  }

  User? _mergeWithDoc(User? base, Map<String, dynamic>? data) {
    if (base == null) return null;
    if (data == null) return base;
    final name = (data['name'] as String?) ?? base.name;
    final email = (data['email'] as String?) ?? base.email;
    final plateNo = data['plateNo'] as String?;
    return base.copyWith(name: name, email: email, plateNo: plateNo);
  }

  // -------- 监听 Firestore users/{uid} 文档；若不存在则创建/迁移 --------
  Future<void> _attachUserDoc(fb.User? u) async {
    _docSub?.cancel();
    if (u == null) return;

    final uidRef = _db.collection('users').doc(u.uid);
    final uidSnap = await uidRef.get();

    if (!uidSnap.exists) {
      // 兼容你当前已有的 “随机 docId” 文档：按 email 搜一次
      if (u.email != null && u.email!.isNotEmpty) {
        final q = await _db
            .collection('users')
            .where('email', isEqualTo: u.email)
            .limit(1)
            .get();

        if (q.docs.isNotEmpty) {
          // 找到了就做一次性“迁移/复制”到 users/{uid}
          final old = q.docs.first;
          final data = Map<String, dynamic>.from(old.data());
          data.remove('password'); // 永远不要保存/复制明文密码
          data['email'] = u.email;
          data['name'] =
              data['name'] ?? (u.displayName ?? u.email!.split('@').first);
          data['updatedAt'] = fs.FieldValue.serverTimestamp();

          await uidRef.set(data, fs.SetOptions(merge: true));
          // 可选：删除旧文档
          // await old.reference.delete();
        } else {
          // 完全没有就创建一个基础档案
          await uidRef.set({
            'email': u.email,
            'name': u.displayName ?? (u.email ?? 'User').split('@').first,
            'plateNo': null,
            'createdAt': fs.FieldValue.serverTimestamp(),
          }, fs.SetOptions(merge: true));
        }
      } else {
        // 没有 email（极少见），仍然创建空白档案
        await uidRef.set({
          'createdAt': fs.FieldValue.serverTimestamp(),
        }, fs.SetOptions(merge: true));
      }
    }

    // 监听 users/{uid} 变化，实时刷新 ProfileBackend.currentUser
    _docSub = uidRef.snapshots().listen((snap) {
      final authUser = _auth.currentUser;
      if (authUser == null) return;
      final base = _mapAuth(authUser);
      _current = _mergeWithDoc(base, snap.data());
    });
  }

  // -------- 对外 API：登录/注册/登出 --------
  @override
  Future<User> signIn(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final mapped = _mapAuth(cred.user);
      if (mapped == null) throw AuthException('Sign-in failed.');
      await _attachUserDoc(cred.user); // 确保监听 & 补档案
      _current = mapped; // 初值，随后由 Firestore 监听完善
      return _current!;
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(_humanize(e));
    }
  }

  @override
  Future<User> register({
    required String name,
    required String email,
    required String password,
    String? plateNo,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await cred.user?.updateDisplayName(name);
      await cred.user?.reload();

      // 建立 users/{uid} 文档（不保存密码）
      final uid = cred.user!.uid;
      await _db.collection('users').doc(uid).set({
        'email': email,
        'name': name,
        'plateNo': plateNo,
        'createdAt': fs.FieldValue.serverTimestamp(),
      }, fs.SetOptions(merge: true));

      final mapped = _mapAuth(_auth.currentUser);
      if (mapped == null) throw AuthException('Registration failed.');
      await _attachUserDoc(_auth.currentUser);
      _current = mapped;
      return _current!;
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(_humanize(e));
    }
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    _docSub?.cancel();
    _current = null;
  }

  String _humanize(fb.FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Invalid email format';
      case 'user-not-found':
        return 'Account not found';
      case 'wrong-password':
        return 'Incorrect password';
      case 'user-disabled':
        return 'Account disabled';
      case 'email-already-in-use':
        return 'Email already registered';
      case 'weak-password':
        return 'Password too weak (min 6 chars)';
      default:
        return e.message ?? 'Auth error: ${e.code}';
    }
  }

  void dispose() {
    _authSub?.cancel();
    _docSub?.cancel();
  }
}
