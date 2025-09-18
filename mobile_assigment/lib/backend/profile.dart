// lib/backend/profile.dart
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:cloud_firestore/cloud_firestore.dart' as fs;

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
}

class User {
  final String id;       // Firebase UID
  final String? userId;  // U001, U002...
  final String name;
  final String email;
  final String? photoUrl;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.userId,
    this.photoUrl,
  });

  User copyWith({
    String? name,
    String? email,
    String? userId,
    String? photoUrl,
  }) =>
      User(
        id: id,
        name: name ?? this.name,
        email: email ?? this.email,
        userId: userId ?? this.userId,
        photoUrl: photoUrl ?? this.photoUrl,
      );
}

/// 統一後端介面
abstract class ProfileBackend {
  static ProfileBackend instance = FirebaseProfileBackend();

  User? get currentUser;

  Future<User> signIn(String email, String password);
  Future<User> register({
    required String name,
    required String email,
    required String password,
  });

  Future<void> signOut();
}

/// =======================
/// Firebase (Auth + Firestore)
/// =======================
class FirebaseProfileBackend implements ProfileBackend {
  final fb.FirebaseAuth _auth = fb.FirebaseAuth.instance;
  final fs.FirebaseFirestore _db = fs.FirebaseFirestore.instance;

  User? _current;
  StreamSubscription<fb.User?>? _authSub;
  StreamSubscription<fs.DocumentSnapshot<Map<String, dynamic>>>? _docSub;

  FirebaseProfileBackend() {
    _current = _mapAuth(_auth.currentUser);
    _authSub = _auth.authStateChanges().listen((u) {
      _current = _mapAuth(u);
      _attachUserDoc(u);
    });
    _attachUserDoc(_auth.currentUser);
  }

  @override
  User? get currentUser => _current;

  // 映射 FirebaseAuth.User -> 本地模型
  User? _mapAuth(fb.User? u) {
    if (u == null) return null;
    final email = u.email ?? '';
    final name =
        u.displayName ?? (email.isNotEmpty ? email.split('@').first : 'User');
    return User(
      id: u.uid,
      name: name,
      email: email,
      userId: null, // 等 Firestore 合併
      photoUrl: u.photoURL,
    );
  }

  // 合併 Firestore users/{uid} 的資料
  User? _mergeWithDoc(User? base, Map<String, dynamic>? data) {
    if (base == null) return null;
    if (data == null) return base;
    return base.copyWith(
      name: data['name'] as String?,
      email: data['email'] as String?,
      userId: data['userId'] as String?,
      photoUrl: data['photoUrl'] as String?,
    );
  }

  /// 監聽 users/{uid}；若不存在或缺 `userId` 就**原子性**建立與編號
  Future<void> _attachUserDoc(fb.User? u) async {
    _docSub?.cancel();
    if (u == null) return;

    final uidRef = _db.collection('users').doc(u.uid);

    // 用 transaction 產生唯一 userId
    await _db.runTransaction((txn) async {
      final userSnap = await txn.get(uidRef);
      final existingUserId = userSnap.data()?['userId'];
      if (existingUserId != null && (existingUserId as String).isNotEmpty) {
        return; // 已有編號，什麼都不做
      }

      final counterRef = _db.collection('meta').doc('counters');
      final counterSnap = await txn.get(counterRef);

      final current = (counterSnap.data()?['userSeq'] ?? 0) as int;
      final next = current + 1;
      final newUserId = 'U${next.toString().padLeft(3, '0')}';

      // 1) 更新計數器
      txn.set(counterRef, {'userSeq': next}, fs.SetOptions(merge: true));

      // 2) 寫入/合併使用者文件
      txn.set(
        uidRef,
        {
          'userId': newUserId,
          'email': u.email,
          'name': u.displayName ?? (u.email ?? 'User').split('@').first,
          'photoUrl': u.photoURL,
          'createdAt': fs.FieldValue.serverTimestamp(),
        },
        fs.SetOptions(merge: true),
      );
    });

    // 即時合併最新文件到本地模型
    _docSub = uidRef.snapshots().listen((doc) {
      _current = _mergeWithDoc(_mapAuth(_auth.currentUser), doc.data());
    });
  }

  @override
  Future<User> signIn(String email, String password) async {
    try {
      final cred =
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      final mapped = _mapAuth(cred.user);
      if (mapped == null) throw AuthException('Sign-in failed.');
      await _attachUserDoc(cred.user); // 確保有 userId
      _current = mapped;
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
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await cred.user?.updateDisplayName(name);
      await cred.user?.reload();

      // 初始化 users/{uid} 並產生 userId
      await _attachUserDoc(cred.user);

      final mapped = _mapAuth(_auth.currentUser);
      if (mapped == null) throw AuthException('Registration failed.');
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
      case 'requires-recent-login':
        return 'Please reauthenticate and try again';
      default:
        return e.message ?? 'Auth error: ${e.code}';
    }
  }

  void dispose() {
    _authSub?.cancel();
    _docSub?.cancel();
  }
}
