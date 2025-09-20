import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';

import '../app_router.dart';
import '../backend/profile.dart';
import '../main.dart';

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
      // Go to the intended page or home.
      final to = widget.redirectTo ?? AppRouter.home;
      Navigator.pushNamedAndRemoveUntil(context, to, (_) => false);
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

    final size = MediaQuery.of(context).size;
    // Make header height responsive. 38% of screen height (min 320, max 420).
    final headerH = size.height.clamp(640, 10000) * 0.38;
    final constrainedHeaderH = headerH.clamp(320.0, 420.0);

    // Logo scales with header (nice and big).
    final logoSize = constrainedHeaderH * 0.60; // ~135–175 px

    return Scaffold(
      extendBodyBehindAppBar:
          true, // Let the header paint behind the AppBar for a clean top
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        // Visible back button so users can exit the login page.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Back',
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            // Ensures the whole page scrolls on small devices/keyboards.
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              // Keep the overall page at least screen height for balanced look.
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ───────────────────────────────── Header
                  Container(
                    height: constrainedHeaderH,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [grabGreen, Color(0xFF05C55A)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(28),
                        bottomRight: Radius.circular(28),
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Big logo centered inside the green header.
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Image.asset(
                              'assets/wms_logo_selected.jpg',
                              width: logoSize,
                              height: logoSize,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Welcome to WMS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Space so the form is visually balanced with the big header.
                  const SizedBox(height: 20),

                  // ──────────────────────────────── Sign-in card
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 4,
                    ),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(.08),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Sign in',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Email
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
                                final ok = RegExp(
                                  r'^[^@]+@[^@]+\.[^@]+$',
                                ).hasMatch(v.trim());
                                return ok ? null : 'Invalid email format';
                              },
                            ),
                            const SizedBox(height: 12),

                            // Password
                            TextFormField(
                              controller: _password,
                              obscureText: _obscure,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(
                                  Icons.lock_outline_rounded,
                                ),
                                suffixIcon: IconButton(
                                  tooltip: _obscure
                                      ? 'Show password'
                                      : 'Hide password',
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

                            // Forgot / Secure labels
                            Row(
                              children: [
                                TextButton(
                                  onPressed: () async {
                                    final email = _email.text.trim();
                                    if (email.isEmpty) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Enter your email first',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    try {
                                      await fb.FirebaseAuth.instance
                                          .sendPasswordResetEmail(email: email);
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
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
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
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

                            const SizedBox(height: 6),

                            // Submit
                            _loading
                                ? const Padding(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 10.0,
                                    ),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                : ElevatedButton(
                                    onPressed: _submit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: grabGreen,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size.fromHeight(48),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 2,
                                    ),
                                    child: const Text(
                                      'Sign in',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),

                            const SizedBox(height: 8),

                            // Go to register
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
                  ),

                  const SizedBox(height: 16),

                  // Terms notice
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 20,
                      right: 20,
                      bottom: 22,
                    ),
                    child: Text(
                      'By continuing, you agree to our Terms & Privacy',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: grabDark.withOpacity(.55),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
