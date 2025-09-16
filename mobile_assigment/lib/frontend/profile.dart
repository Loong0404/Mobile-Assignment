import 'dart:convert'; // 用于Base64编码
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_router.dart';
import '../main.dart';
import '../backend/profile.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:image_picker/image_picker.dart';

/// =======================
/// Login
/// =======================
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.redirectTo});
  final String? redirectTo;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ProfileBackend.instance.signIn(_email.text.trim(), _password.text);
      if (!mounted) return;
      if (widget.redirectTo != null) {
        Navigator.pushReplacementNamed(context, widget.redirectTo!);
      } else {
        Navigator.pushReplacementNamed(context, AppRouter.home);
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const grabGreen = WmsApp.grabGreen;
    const grabDark = WmsApp.grabDark;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          Container(
            height: 260,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [grabGreen, Color(0xFF05C55A)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
              child: Column(
                children: [
                  const SizedBox(height: 28),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Welcome back',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Sign in to manage your vehicle service',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(.06),
                          blurRadius: 12,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _form,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              hintText: 'name@example.com',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty)
                                return 'Please enter your email';
                              final ok = RegExp(
                                r'^[^@]+@[^@]+\.[^@]+$',
                              ).hasMatch(v.trim());
                              return ok ? null : 'Invalid email format';
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: _obscure,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Please enter your password';
                              }
                              if (v.length < 6) {
                                return 'Password must be at least 6 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () async {
                                  final email = _email.text.trim();
                                  if (email.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Enter your email first'),
                                      ),
                                    );
                                    return;
                                  }
                                  try {
                                    await fb.FirebaseAuth.instance
                                        .sendPasswordResetEmail(email: email);
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Password reset email sent to $email',
                                        ),
                                      ),
                                    );
                                  } on fb.FirebaseAuthException catch (e) {
                                    if (!mounted) return;
                                    final msg =
                                        e.message ??
                                        'Failed to send reset email';
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(msg)),
                                    );
                                  }
                                },
                                child: const Text('Forgot password?'),
                              ),
                              const Spacer(),
                              Text(
                                'Secure login',
                                style: TextStyle(
                                  color: grabDark.withOpacity(.55),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _loading
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8.0),
                                  child: CircularProgressIndicator(),
                                )
                              : ElevatedButton(
                                  onPressed: _submit,
                                  child: const Text('Sign in'),
                                ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Don't have an account?",
                                style: TextStyle(
                                  color: grabDark.withOpacity(.8),
                                ),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pushNamed(
                                  context,
                                  AppRouter.register,
                                ),
                                child: const Text('Create account'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'By continuing, you agree to our Terms & Privacy',
                    style: TextStyle(
                      color: WmsApp.grabDark.withOpacity(.55),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// =======================
/// Register
/// =======================
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure1 = true, _obscure2 = true;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ProfileBackend.instance.register(
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, AppRouter.home, (_) => false);
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const grabGreen = WmsApp.grabGreen;

    return Scaffold(
      appBar: AppBar(title: const Text('Create your account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: grabGreen.withOpacity(.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Join WMS — book services, track progress, and pay bills easily.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Please enter your name'
                    : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'name@example.com',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Please enter your email';
                  }
                  final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v.trim());
                  return ok ? null : 'Invalid email format';
                },
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _password,
                obscureText: _obscure1,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure1 = !_obscure1),
                    icon: Icon(
                      _obscure1 ? Icons.visibility : Icons.visibility_off,
                    ),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Please set a password';
                  if (v.length < 6) return 'At least 6 characters';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _confirm,
                obscureText: _obscure2,
                decoration: InputDecoration(
                  labelText: 'Confirm password',
                  prefixIcon: const Icon(Icons.lock_person_outlined),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure2 = !_obscure2),
                    icon: Icon(
                      _obscure2 ? Icons.visibility : Icons.visibility_off,
                    ),
                  ),
                ),
                validator: (v) =>
                    (v != _password.text) ? 'Passwords do not match' : null,
              ),
              const SizedBox(height: 16),

              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _submit,
                      child: const Text('Create account'),
                    ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () =>
                      Navigator.pushReplacementNamed(context, AppRouter.login),
                  child: const Text('Already have an account? Sign in'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// =======================
/// Profile（可編輯 + vehicles）
/// =======================
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  // ---- 硬編碼 Service history（倒序） ----
  List<_ServiceHistory> _demoHistory() => [
    _ServiceHistory(
      date: DateTime(2025, 6, 15),
      type: 'Maintenance A',
      workshop: 'WMS Petaling Jaya',
      mileage: 45210,
      amount: 320.00,
    ),
    _ServiceHistory(
      date: DateTime(2024, 12, 10),
      type: 'Brake Pad Replacement',
      workshop: 'WMS Shah Alam',
      mileage: 39800,
      amount: 560.00,
    ),
    _ServiceHistory(
      date: DateTime(2024, 6, 5),
      type: 'Inspection',
      workshop: 'WMS Subang',
      mileage: 35200,
      amount: 0.00,
    ),
  ]..sort((a, b) => b.date.compareTo(a.date));

  // ---- 更換頭像（使用Base64存储） ----
  Future<void> _changePhoto(BuildContext context) async {
    try {
      final user = fb.FirebaseAuth.instance.currentUser!;
      final picker = ImagePicker();

      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 400, // 限制图片大小
        maxHeight: 400,
        imageQuality: 70, // 降低质量以减少大小
      );

      if (picked == null) return;

      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Processing image...')));

      // 读取图片数据并转换为Base64
      final bytes = await picked.readAsBytes();
      final base64Image = base64Encode(bytes);

      // 检查大小（Firestore文档限制为1MB）
      if (base64Image.length > 900000) {
        // 留出一些空间给其他字段
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image is too large. Please choose a smaller image.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // 更新 Firestore
      await fs.FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'photoUrl': null, // 清除可能存在的旧URL
          'photoBase64': base64Image, // 存储Base64图片数据
          'updatedAt': fs.FieldValue.serverTimestamp(),
        },
        fs.SetOptions(merge: true),
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile photo updated successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating photo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ---- 編輯名稱 ----
  Future<void> _editName(BuildContext context, String initial) async {
    final ctrl = TextEditingController(text: initial);
    final form = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit name'),
        content: Form(
          key: form,
          child: TextFormField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'Full name'),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Please enter your name'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!(form.currentState?.validate() ?? false)) return;
              final name = ctrl.text.trim();
              final u = fb.FirebaseAuth.instance.currentUser!;
              await u.updateDisplayName(name);
              await fs.FirebaseFirestore.instance
                  .collection('users')
                  .doc(u.uid)
                  .set({
                    'name': name,
                    'updatedAt': fs.FieldValue.serverTimestamp(),
                  }, fs.SetOptions(merge: true));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ---- 通用 reauth ----
  Future<bool> _reauth(BuildContext context, String email) async {
    final pwdCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reauthenticate'),
        content: TextField(
          controller: pwdCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Current password'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    try {
      final cred = fb.EmailAuthProvider.credential(
        email: email,
        password: pwdCtrl.text,
      );
      await fb.FirebaseAuth.instance.currentUser!.reauthenticateWithCredential(
        cred,
      );
      return true;
    } on fb.FirebaseAuthException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message ?? 'Reauth failed')));
      }
      return false;
    }
  }

  // ---- 編輯 Email ----
  Future<void> _editEmail(BuildContext context, String currentEmail) async {
    final emailCtrl = TextEditingController(text: currentEmail);
    final form = GlobalKey<FormState>();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Change email'),
        content: Form(
          key: form,
          child: TextFormField(
            controller: emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'New email'),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Enter new email';
              final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v.trim());
              return ok ? null : 'Invalid email format';
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!(form.currentState?.validate() ?? false)) return;
              final user = fb.FirebaseAuth.instance.currentUser!;
              final newEmail = emailCtrl.text.trim();
              if (!await _reauth(context, user.email ?? '')) return;
              await user.verifyBeforeUpdateEmail(newEmail);
              await fs.FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .set({
                    'email': newEmail,
                    'updatedAt': fs.FieldValue.serverTimestamp(),
                  }, fs.SetOptions(merge: true));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ---- 修改密碼 ----
  Future<void> _changePassword(BuildContext context, String email) async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final form = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Change password'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: currentCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current password',
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Enter current password' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: newCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New password (min 6 chars)',
                ),
                validator: (v) => (v == null || v.length < 6)
                    ? 'At least 6 characters'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!(form.currentState?.validate() ?? false)) return;
              try {
                final cred = fb.EmailAuthProvider.credential(
                  email: email,
                  password: currentCtrl.text,
                );
                final user = fb.FirebaseAuth.instance.currentUser!;
                await user.reauthenticateWithCredential(cred);
                await user.updatePassword(newCtrl.text);
                if (context.mounted) Navigator.pop(context);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password updated')),
                  );
                }
              } on fb.FirebaseAuthException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.message ?? 'Failed to update')),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ---- 新增/編輯 Vehicle ----
  Future<void> _editVehicle(
    BuildContext context, {
    String? docId,
    String? plate,
    String? brand,
  }) async {
    final uid = ProfileBackend.instance.currentUser!.id;
    final userId = ProfileBackend.instance.currentUser!.userId;
    final plateCtrl = TextEditingController(text: plate ?? '');
    final brandCtrl = TextEditingController(text: brand ?? '');
    final form = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(docId == null ? 'Add vehicle' : 'Edit vehicle'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: plateCtrl,
                decoration: const InputDecoration(labelText: 'Plate number'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter plate number'
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: brandCtrl,
                decoration: const InputDecoration(
                  labelText: 'Brand (e.g., Toyota, Honda)',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter brand' : null,
              ),
            ],
          ),
        ),
        actions: [
          if (docId != null)
            TextButton(
              onPressed: () async {
                await fs.FirebaseFirestore.instance
                    .collection('vehicle')
                    .doc(docId)
                    .delete();
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!(form.currentState?.validate() ?? false)) return;
              final data = {
                'plateNumber': plateCtrl.text.trim(),
                'carType': brandCtrl.text.trim(),
                'userUid': uid,
                'userId': userId,
                'updatedAt': fs.FieldValue.serverTimestamp(),
              };
              if (docId == null) {
                await fs.FirebaseFirestore.instance.collection('vehicle').add({
                  ...data,
                  'createdAt': fs.FieldValue.serverTimestamp(),
                });
              } else {
                await fs.FirebaseFirestore.instance
                    .collection('vehicle')
                    .doc(docId)
                    .set(data, fs.SetOptions(merge: true));
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authUser = fb.FirebaseAuth.instance.currentUser;
    final backendUser = ProfileBackend.instance.currentUser;

    if (authUser == null || backendUser == null) {
      return const Scaffold(
        body: Center(child: Text('No user (should be redirected to login).')),
      );
    }

    final uid = backendUser.id;
    final userDocStream = fs.FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots();

    // 重要：去掉 orderBy 避免需要建立複合索引導致一直 loading
    final vehiclesStream = fs.FirebaseFirestore.instance
        .collection('vehicle')
        .where('userUid', isEqualTo: uid)
        .snapshots();

    final history = _demoHistory();
    final lastService = history.isNotEmpty ? history.first.date : null;
    final nextService = lastService?.add(const Duration(days: 365));
    String humanDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
    String nextServiceText() {
      if (nextService == null) return '—';
      final days = nextService.difference(DateTime.now()).inDays;
      final when = humanDate(nextService);
      if (days > 0) return '$when  • in $days days';
      if (days == 0) return '$when  • today';
      return '$when  • overdue by ${-days} days';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: StreamBuilder<fs.DocumentSnapshot<Map<String, dynamic>>>(
        stream: userDocStream,
        builder: (context, snap) {
          final doc = snap.data?.data();
          final name = (doc?['name'] ?? backendUser.name) as String;
          final email = (doc?['email'] ?? backendUser.email) as String;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ===== Header: Avatar + Name/Email/UserId =====
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      StreamBuilder<fs.DocumentSnapshot>(
                        stream: fs.FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const CircleAvatar(
                              radius: 34,
                              child: Icon(Icons.person, size: 34),
                            );
                          }

                          final data =
                              snapshot.data!.data() as Map<String, dynamic>?;
                          final base64Image = data?['photoBase64'] as String?;

                          if (base64Image == null || base64Image.isEmpty) {
                            return const CircleAvatar(
                              radius: 34,
                              child: Icon(Icons.person, size: 34),
                            );
                          }

                          try {
                            return CircleAvatar(
                              radius: 34,
                              backgroundImage: MemoryImage(
                                base64Decode(base64Image),
                              ),
                            );
                          } catch (e) {
                            return const CircleAvatar(
                              radius: 34,
                              child: Icon(Icons.person, size: 34),
                            );
                          }
                        },
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              email,
                              style: const TextStyle(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Change photo',
                        onPressed: () => _changePhoto(context),
                        icon: const Icon(Icons.photo_camera_outlined),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ===== Editable rows: Name / Email / Password =====
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: const Text('Name'),
                      subtitle: Text(name),
                      trailing: TextButton.icon(
                        onPressed: () => _editName(context, name),
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Edit'),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.email_outlined),
                      title: const Text('Email'),
                      subtitle: Text(email),
                      trailing: TextButton.icon(
                        onPressed: () => _editEmail(context, email),
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Edit'),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: const Text('Password'),
                      subtitle: const Text('Change your password'),
                      trailing: TextButton.icon(
                        onPressed: () => _changePassword(context, email),
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Change'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ===== Vehicles =====
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Vehicles',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _editVehicle(context),
                            icon: const Icon(Icons.add),
                            label: const Text('Add'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      StreamBuilder<fs.QuerySnapshot<Map<String, dynamic>>>(
                        stream: vehiclesStream,
                        builder: (context, vSnap) {
                          if (vSnap.hasError) {
                            return Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                'Error: ${vSnap.error}',
                                style: const TextStyle(color: Colors.red),
                              ),
                            );
                          }
                          if (!vSnap.hasData) {
                            return const Padding(
                              padding: EdgeInsets.all(8),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          // 客戶端排序：createdAt desc（若缺失則放最後）
                          final docs = [...vSnap.data!.docs];
                          docs.sort((a, b) {
                            final ta = a.data()['createdAt'];
                            final tb = b.data()['createdAt'];
                            if (ta == null && tb == null) return 0;
                            if (ta == null) return 1;
                            if (tb == null) return -1;
                            return (tb as fs.Timestamp).compareTo(
                              ta as fs.Timestamp,
                            );
                          });
                          if (docs.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(8),
                              child: Text('No vehicles yet.'),
                            );
                          }
                          return ListView.separated(
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: docs.length,
                            itemBuilder: (_, i) {
                              final d = docs[i];
                              final plate = d['plateNumber'] as String? ?? '';
                              final brand = d['carType'] as String? ?? '';
                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.directions_car_outlined,
                                ),
                                title: Text(plate),
                                subtitle: Text(brand),
                                trailing: TextButton.icon(
                                  onPressed: () => _editVehicle(
                                    context,
                                    docId: d.id,
                                    plate: plate,
                                    brand: brand,
                                  ),
                                  icon: const Icon(Icons.edit, size: 18),
                                  label: const Text('Edit'),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ===== Estimated next service =====
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  leading: const Icon(Icons.schedule),
                  title: const Text('Estimated time for next service'),
                  subtitle: Text(nextServiceText()),
                ),
              ),
              const SizedBox(height: 12),

              // ===== Service history (hardcoded) =====
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Service history',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      ListView.separated(
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: history.length,
                        itemBuilder: (_, i) {
                          final h = history[i];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.build_circle_outlined),
                            title: Text(h.type),
                            subtitle: Text(
                              '${humanDate(h.date)} • ${h.workshop} • ${h.mileage} km',
                            ),
                            trailing: Text('RM ${h.amount.toStringAsFixed(2)}'),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ===== Sign out =====
              Center(
                child: ElevatedButton(
                  onPressed: () async {
                    await ProfileBackend.instance.signOut();
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Sign out'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ServiceHistory {
  final DateTime date;
  final String type;
  final String workshop;
  final int mileage;
  final double amount;
  _ServiceHistory({
    required this.date,
    required this.type,
    required this.workshop,
    required this.mileage,
    required this.amount,
  });
}
