import 'package:flutter/material.dart';
import '../app_router.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Appointments', AppRouter.appointments),
      ('Booking', AppRouter.booking),
      ('Tracking', AppRouter.tracking),
      ('Billing', AppRouter.billing),
      ('Feedback', AppRouter.feedback),
      ('Notices', AppRouter.notices),
      ('Profile', AppRouter.profile),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('WMS Customer')),
      body: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final (title, route) = items[i];
          return ListTile(
            title: Text(title),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onTap: () => Navigator.pushNamed(context, route),
          );
        },
      ),
    );
  }
}
