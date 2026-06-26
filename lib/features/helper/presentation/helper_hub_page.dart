import 'package:flutter/material.dart';
import 'tabs/find_helper_tab.dart';
import 'tabs/register_helper_tab.dart';
import '../../../core/services/auth_service.dart';
import 'helper_jobs_page.dart';

class HelperHubPage extends StatefulWidget {
  const HelperHubPage({super.key});

  @override
  State<HelperHubPage> createState() => _HelperHubPageState();
}

class _HelperHubPageState extends State<HelperHubPage> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Helper Hub'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.search), text: 'Find a Helper'),
              Tab(icon: Icon(Icons.handyman), text: 'Become a Helper'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            FindHelperTab(),
            RegisterHelperTab(),
          ],
        ),
        floatingActionButton: AuthService.isLoggedIn
            ? FloatingActionButton.extended(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const HelperJobsPage()),
                  );
                },
                icon: const Icon(Icons.work),
                label: Text(AuthService.currentUser?.primaryRole == 'helper' ? 'My Jobs' : 'Hired Helpers'),
              )
            : null,
      ),
    );
  }
}
