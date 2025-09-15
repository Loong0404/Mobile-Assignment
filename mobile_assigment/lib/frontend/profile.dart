import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_router.dart';
import '../main.dart';
import '../backend/profile.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:cloud_firestore/cloud_firestore.dart' as fs;

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
                              if (v == null || v.isEmpty)
                                return 'Please enter your password';
                              if (v.length < 6)
                                return 'Password must be at least 6 characters';
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
                                    // 這個調用會「真的寄出」重置密碼的 email
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
                      color: grabDark.withOpacity(.55),
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
  final _plate = TextEditingController();
  bool _obscure1 = true, _obscure2 = true;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _plate.dispose();
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
        plateNo: _plate.text.trim(), // Firestore 由 backend 寫入 users/{uid}
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
                  if (v == null || v.trim().isEmpty)
                    return 'Please enter your email';
                  final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v.trim());
                  return ok ? null : 'Invalid email format';
                },
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _plate,
                decoration: const InputDecoration(
                  labelText: 'Car plate (optional)',
                  prefixIcon: Icon(Icons.directions_car_outlined),
                ),
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
/// Profile
/// =======================
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  // —— 硬編碼服務歷史（倒序）——
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

  Future<void> _editPlate(BuildContext context, String initial) async {
    final uid = ProfileBackend.instance.currentUser!.id;
    final ctrl = TextEditingController(text: initial);
    final form = GlobalKey<FormState>();
    final focus = FocusNode();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit car plate'),
        content: Form(
          key: form,
          child: TextFormField(
            controller: ctrl,
            focusNode: focus,
            decoration: const InputDecoration(
              labelText: 'Plate number',
              hintText: 'e.g., VBA1234',
            ),
            validator: (v) {
              if (v == null) return null;
              final t = v.trim();
              if (t.isEmpty) return 'Please enter a plate number';
              return null;
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
              await fs.FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .set({
                    'plateNo': ctrl.text.trim(),
                    'updatedAt': fs.FieldValue.serverTimestamp(),
                  }, fs.SetOptions(merge: true));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    focus.dispose();
    ctrl.dispose();
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
    final history = _demoHistory(); // 硬編碼歷史
    final lastService = history.isNotEmpty ? history.first.date : null;
    final nextService = lastService?.add(
      const Duration(days: 365),
    ); // 估算：最近一次 + 1 年

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
          final plate = (doc?['plateNo'] ?? backendUser.plateNo) as String?;
          final photoUrl = authUser.photoURL;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ===== Header: Avatar + Name/Email =====
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundImage:
                            (photoUrl != null && photoUrl.isNotEmpty)
                            ? NetworkImage(photoUrl)
                            : null,
                        child: (photoUrl == null || photoUrl.isEmpty)
                            ? const Icon(Icons.person, size: 34)
                            : null,
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
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ===== Car plate =====
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  leading: const Icon(Icons.directions_car_outlined),
                  title: const Text('Car plate'),
                  subtitle: Text(plate ?? '—'),
                  trailing: TextButton.icon(
                    onPressed: () => _editPlate(context, plate ?? ''),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Edit'),
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

/// 簡單的服務歷史模型（僅供本頁硬編碼展示）
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
