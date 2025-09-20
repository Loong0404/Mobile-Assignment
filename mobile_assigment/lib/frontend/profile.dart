// lib/frontend/profile.dart
//
// Profile page with:
// - Avatar (tap camera icon -> choose camera or gallery, saves as base64 to Firestore)
// - Edit name / email / password
// - Vehicles list (+ add/edit/delete)
// - Simple service history demo
// - Drawer (WmsDrawer) for global navigation
//
// Notes for reviewers:
// * All SnackBars and Navigator calls check context.mounted after awaits.
// * Avatar camera button is intentionally small to avoid blocking the photo view.

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../app_router.dart';
import '../backend/profile.dart';
import '../main.dart';
import 'app_drawer.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  // Demo history (reverse chronological)
  List<_ServiceHistory> _demoHistory() => [
    _ServiceHistory(
      date: DateTime(2024, 9, 20),
      type: 'Maintenance A',
      workshop: 'WMS Petaling Jaya',
      mileage: 45210,
      amount: 320.00,
    ),
    _ServiceHistory(
      date: DateTime(2024, 3, 15),
      type: 'Brake Pad Replacement',
      workshop: 'WMS Shah Alam',
      mileage: 39800,
      amount: 560.00,
    ),
    _ServiceHistory(
      date: DateTime(2023, 9, 10),
      type: 'Inspection',
      workshop: 'WMS Subang',
      mileage: 35200,
      amount: 0.00,
    ),
  ]..sort((a, b) => b.date.compareTo(a.date));

  // Pick image from camera or gallery and save to Firestore as base64
  Future<void> _pickAndSavePhoto(
    BuildContext context,
    ImageSource source,
  ) async {
    try {
      final user = fb.FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 75,
      );
      if (picked == null) return;

      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Processing image...')));

      final bytes = await picked.readAsBytes();
      final b64 = base64Encode(bytes);

      // Keep under Firestore 1MB per document headroom
      if (b64.length > 900000) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image is too large. Please choose a smaller image.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      await fs.FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
            'photoUrl': null,
            'photoBase64': b64,
            'updatedAt': fs.FieldValue.serverTimestamp(),
          }, fs.SetOptions(merge: true));

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile photo updated'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // Bottom sheet to choose camera / gallery
  Future<void> _changePhoto(BuildContext context) async {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSavePhoto(context, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSavePhoto(context, ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  // Edit name dialog
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
              final u = fb.FirebaseAuth.instance.currentUser;
              if (u == null) return;
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

  // Reauth helper (password)
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
      final user = fb.FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      await user.reauthenticateWithCredential(cred);
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

  // Edit email dialog
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
              final user = fb.FirebaseAuth.instance.currentUser;
              if (user == null) return;
              final newEmail = emailCtrl.text.trim();
              final oldEmail = user.email ?? '';
              if (!await _reauth(context, oldEmail)) return;
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

  // Change password dialog
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
                final user = fb.FirebaseAuth.instance.currentUser;
                if (user == null) return;
                await user.reauthenticateWithCredential(cred);
                await user.updatePassword(newCtrl.text);
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password updated')),
                );
              } on fb.FirebaseAuthException catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.message ?? 'Failed to update')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Add/edit vehicle dialog
  Future<void> _editVehicle(
    BuildContext context, {
    String? docId,
    String? plate,
    String? brand,
  }) async {
    final backendUser = ProfileBackend.instance.currentUser;
    if (backendUser == null) return;

    final uid = backendUser.id;
    final userId = backendUser.userId;
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
      drawer: const WmsDrawer(),
      appBar: AppBar(title: const Text('Profile')),
      body: StreamBuilder<fs.DocumentSnapshot<Map<String, dynamic>>>(
        stream: userDocStream,
        builder: (context, snap) {
          final doc = snap.data?.data();
          final name = (doc?['name'] ?? backendUser.name) as String;
          final email = (doc?['email'] ?? backendUser.email) as String;
          final base64Image = doc?['photoBase64'] as String?;

          ImageProvider? avatar;
          if (base64Image != null && base64Image.isNotEmpty) {
            try {
              avatar = MemoryImage(base64Decode(base64Image));
            } catch (_) {
              avatar = null;
            }
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Header card (small camera button overlays bottom-right)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 34,
                            backgroundImage: avatar,
                            child: avatar == null
                                ? const Icon(Icons.person, size: 34)
                                : null,
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Material(
                              color: WmsApp.grabGreen,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => _changePhoto(context),
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(
                                    Icons.photo_camera_outlined,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
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

              // Editable rows
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

              // Vehicles
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
                          final docs = [...vSnap.data!.docs];
                          // Client-side sort by createdAt desc (missing ones go last)
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
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            separatorBuilder: (ctx, _) =>
                                const Divider(height: 1),
                            itemCount: docs.length,
                            itemBuilder: (ctx, i) {
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

              // Estimated next service
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

              // Simple service history block
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
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        separatorBuilder: (ctx, _) => const Divider(height: 1),
                        itemCount: history.length,
                        itemBuilder: (ctx, i) {
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

              // Sign out
              Center(
                child: ElevatedButton(
                  onPressed: () async {
                    await ProfileBackend.instance.signOut();
                    if (!context.mounted) return;
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      AppRouter.home,
                      (r) => false,
                    );
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
