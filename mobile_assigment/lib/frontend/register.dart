// lib/frontend/register.dart
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';

import '../app_router.dart';
import '../backend/profile.dart';
import '../main.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _plate = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure1 = true, _obscure2 = true;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _plate.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<bool> _emailExists(String email) async {
    final q = await fs.FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    return q.docs.isNotEmpty;
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;

    final name = _name.text.trim();
    final email = _email.text.trim();
    final plate = _plate.text.trim();
    final pwd = _password.text;

    setState(() => _loading = true);
    try {
      // 1) Check duplicate email in Firestore
      if (await _emailExists(email)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This email is already registered.')),
        );
        setState(() => _loading = false);
        return;
      }

      // 2) Register with backend (Firebase Auth + users doc)
      await ProfileBackend.instance.register(
        name: name,
        email: email,
        password: pwd,
      );

      // 3) Add plateNo into users doc, and create a vehicle record
      final uid = fb.FirebaseAuth.instance.currentUser!.uid;
      final userDocRef = fs.FirebaseFirestore.instance
          .collection('users')
          .doc(uid);
      await userDocRef.set({
        'plateNo': plate,
        'updatedAt': fs.FieldValue.serverTimestamp(),
      }, fs.SetOptions(merge: true));

      // You'll likely have an incremental 'userId' generator already in backend.
      // We also create the first vehicle document visible in Profile > Vehicles.
      final userSnap = await userDocRef.get();
      final userId = (userSnap.data()?['userId'] ?? '') as String;
      await fs.FirebaseFirestore.instance.collection('vehicle').add({
        'plateNumber': plate,
        'carType': '',
        'userUid': uid,
        'userId': userId,
        'createdAt': fs.FieldValue.serverTimestamp(),
        'updatedAt': fs.FieldValue.serverTimestamp(),
      });

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

              // Car plate (required)
              TextFormField(
                controller: _plate,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Car plate',
                  prefixIcon: Icon(Icons.directions_car_outlined),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Car plate is required'
                    : null,
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
