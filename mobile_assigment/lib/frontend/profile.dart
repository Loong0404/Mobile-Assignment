// lib/frontend/profile.dart
// Profile page (clickable avatar + edit name/email/password + vehicles + history)

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../backend/profile.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:image_picker/image_picker.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // ---- 硬編碼 Service history（倒序） ----
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

  // ---- 更換頭像（整個頭像可點 + 右上角相機可點） ----
  Future<void> _changePhoto() async {
    try {
      final authUser = fb.FirebaseAuth.instance.currentUser;
      if (authUser == null) return;

      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 70, // 壓縮避免 Firestore 單文件 1MB 限制
      );
      if (picked == null) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Processing image...')),
      );

      final bytes = await picked.readAsBytes();
      final base64Image = base64Encode(bytes);

      if (base64Image.length > 900000) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image too large. Please choose a smaller one.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      await fs.FirebaseFirestore.instance
          .collection('users')
          .doc(authUser.uid)
          .set(
        {
          'photoUrl': null, // 清掉舊的 URL 欄位
          'photoBase64': base64Image,
          'updatedAt': fs.FieldValue.serverTimestamp(),
        },
        fs.SetOptions(merge: true),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile photo updated'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update photo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ---- 編輯名稱 ----
  Future<void> _editName(String initial) async {
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
            validator: (v) =>
            (v == null || v.trim().isEmpty) ? 'Please enter your name' : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (!(form.currentState?.validate() ?? false)) return;
              final name = ctrl.text.trim();
              final u = fb.FirebaseAuth.instance.currentUser!;
              await u.updateDisplayName(name);
              await fs.FirebaseFirestore.instance.collection('users').doc(u.uid).set(
                {
                  'name': name,
                  'updatedAt': fs.FieldValue.serverTimestamp(),
                },
                fs.SetOptions(merge: true),
              );
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ---- 通用 reauth ----
  Future<bool> _reauth(String email) async {
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
        ],
      ),
    );
    if (ok != true) return false;

    try {
      final cred =
      fb.EmailAuthProvider.credential(email: email, password: pwdCtrl.text);
      await fb.FirebaseAuth.instance.currentUser!.reauthenticateWithCredential(cred);
      return true;
    } on fb.FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Reauth failed')),
        );
      }
      return false;
    }
  }

  // ---- 編輯 Email ----
  Future<void> _editEmail(String currentEmail) async {
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (!(form.currentState?.validate() ?? false)) return;
              final user = fb.FirebaseAuth.instance.currentUser!;
              final newEmail = emailCtrl.text.trim();
              if (!await _reauth(user.email ?? '')) return;
              await user.verifyBeforeUpdateEmail(newEmail);
              await fs.FirebaseFirestore.instance.collection('users').doc(user.uid).set(
                {
                  'email': newEmail,
                  'updatedAt': fs.FieldValue.serverTimestamp(),
                },
                fs.SetOptions(merge: true),
              );
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ---- 修改密碼 ----
  Future<void> _changePassword(String email) async {
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
                decoration: const InputDecoration(labelText: 'Current password'),
                validator: (v) =>
                (v == null || v.isEmpty) ? 'Enter current password' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: newCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password (min 6 chars)'),
                validator: (v) =>
                (v == null || v.length < 6) ? 'At least 6 characters' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
                if (mounted) Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password updated')),
                  );
                }
              } on fb.FirebaseAuthException catch (e) {
                if (mounted) {
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
  Future<void> _editVehicle({
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
                validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter plate number' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: brandCtrl,
                decoration:
                const InputDecoration(labelText: 'Brand (e.g., Toyota, Honda)'),
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
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
              if (mounted) Navigator.pop(context);
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
    final userDocStream =
    fs.FirebaseFirestore.instance.collection('users').doc(uid).snapshots();

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
              // ===== Header: Avatar（可點擊） + Name/Email/UserId =====
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // 以 Stack 疊加小相機按鈕；整個頭像與相機都可點
                      StreamBuilder<fs.DocumentSnapshot>(
                        stream: fs.FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .snapshots(),
                        builder: (context, snapshot) {
                          String? base64Image;
                          if (snapshot.hasData) {
                            final data =
                            snapshot.data!.data() as Map<String, dynamic>?;
                            base64Image = data?['photoBase64'] as String?;
                          }

                          Widget avatar;
                          if (base64Image == null || base64Image.isEmpty) {
                            avatar = const CircleAvatar(
                              radius: 38,
                              child: Icon(Icons.person, size: 34),
                            );
                          } else {
                            try {
                              avatar = CircleAvatar(
                                radius: 38,
                                backgroundImage: MemoryImage(
                                  base64Decode(base64Image),
                                ),
                              );
                            } catch (_) {
                              avatar = const CircleAvatar(
                                radius: 38,
                                child: Icon(Icons.person, size: 34),
                              );
                            }
                          }

                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // 整個頭像可點
                              InkWell(
                                onTap: _changePhoto,
                                borderRadius: BorderRadius.circular(44),
                                child: avatar,
                              ),
                              // 右下角小相機
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: Material(
                                  color: Colors.white,
                                  shape: const CircleBorder(),
                                  elevation: 2,
                                  child: InkWell(
                                    onTap: _changePhoto,
                                    customBorder: const CircleBorder(),
                                    child: const Padding(
                                      padding: EdgeInsets.all(6),
                                      child: Icon(
                                        Icons.photo_camera_outlined,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
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
                            Text(email, style: const TextStyle(color: Colors.black54)),
                          ],
                        ),
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
                        onPressed: () => _editName(name),
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
                        onPressed: () => _editEmail(email),
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
                        onPressed: () => _changePassword(email),
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
                            onPressed: () => _editVehicle(),
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
                          docs.sort((a, b) {
                            final ta = a.data()['createdAt'];
                            final tb = b.data()['createdAt'];
                            if (ta == null && tb == null) return 0;
                            if (ta == null) return 1;
                            if (tb == null) return -1;
                            return (tb as fs.Timestamp).compareTo(ta as fs.Timestamp);
                          });
                          if (docs.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(8),
                              child: Text('No vehicles yet.'),
                            );
                          }
                          return ListView.separated(
                            separatorBuilder: (_, __) => const Divider(height: 1),
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
                                leading: const Icon(Icons.directions_car_outlined),
                                title: Text(plate),
                                subtitle: Text(brand),
                                trailing: TextButton.icon(
                                  onPressed: () => _editVehicle(
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
                      const Text('Service history',
                          style: TextStyle(fontWeight: FontWeight.w600)),
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
                            subtitle:
                            Text('${humanDate(h.date)} • ${h.workshop} • ${h.mileage} km'),
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
                    if (mounted) Navigator.pop(context);
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
