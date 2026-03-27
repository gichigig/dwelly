import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'my_reports_page.dart';
import 'muted_blocked_contacts_page.dart';

class ReportsSafetyCenterPage extends StatelessWidget {
  const ReportsSafetyCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports & Safety')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('My Reports'),
                  subtitle: const Text('Track report status and outcomes'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MyReportsPage()),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('Report Outcomes'),
                  subtitle: const Text('Decisions and actions from moderation'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MyReportsPage()),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.gavel_outlined),
                  title: const Text('Appeal Decision'),
                  subtitle: const Text(
                    'Contact support to appeal moderation outcomes',
                  ),
                  onTap: () async {
                    await launchUrl(
                      Uri.parse(
                        'mailto:support@bluvberry.tech?subject=Appeal%20Decision',
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.block_outlined),
                  title: const Text('Muted/Blocked Contacts'),
                  subtitle: const Text(
                    'Manage muted notifications and blocked chats',
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MutedBlockedContactsPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
