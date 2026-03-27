import 'package:flutter/material.dart';
import '../../../core/widgets/top_notification_bell.dart';
import '../../rentals/presentation/rentals_explore_view.dart';
import '../../lost_id/presentation/lost_id_view.dart';
import 'explore_mode.dart';

class ExploreHubPage extends StatefulWidget {
  const ExploreHubPage({super.key});

  @override
  State<ExploreHubPage> createState() => _ExploreHubPageState();
}

class _ExploreHubPageState extends State<ExploreHubPage> {
  ExploreMode _mode = ExploreMode.rentals;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Explore'),
        actions: const [TopNotificationBell()],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SegmentedButton<ExploreMode>(
              segments: const [
                ButtonSegment(
                  value: ExploreMode.rentals,
                  label: Text('Rent'),
                  icon: Icon(Icons.home_outlined),
                ),
                ButtonSegment(
                  value: ExploreMode.lostId,
                  label: Text('Lost ID'),
                  icon: Icon(Icons.badge_outlined),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _mode == ExploreMode.rentals ? 0 : 1,
        children: const [
          RentalsExploreView(key: ValueKey('rentals')),
          LostIdView(key: ValueKey('lostid')),
        ],
      ),
    );
  }
}
