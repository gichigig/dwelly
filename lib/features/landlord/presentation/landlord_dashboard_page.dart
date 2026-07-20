import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/api_service.dart';
import '../../../core/widgets/dwelly_orbiting_loader.dart';
import '../../../core/models/rental.dart';
import '../services/landlord_service.dart';
import 'landlord_create_building_page.dart';
import 'landlord_edit_building_page.dart';
import 'landlord_create_rental_page.dart';
import 'landlord_edit_rental_page.dart';

class LandlordDashboardPage extends StatefulWidget {
  const LandlordDashboardPage({super.key});

  @override
  State<LandlordDashboardPage> createState() => _LandlordDashboardPageState();
}

class _LandlordDashboardPageState extends State<LandlordDashboardPage> {
  bool _isLoading = true;
  List<dynamic> _buildings = [];
  List<Rental> _rentals = [];
  int _visibleRentalsLimit = 10;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final futures = await Future.wait([
        LandlordService.getMyBuildings(),
        LandlordService.getMyRentals(),
      ]);
      _buildings = futures[0] as List<dynamic>;
      _rentals = futures[1] as List<Rental>;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading landlord data: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildProfileCard() {
    final user = AuthService.currentUser;
    if (user == null) return const SizedBox.shrink();

    return Card(
      elevation: 0,
      color: Colors.blue.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundImage:
                  user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                  ? CachedNetworkImageProvider(
                          ApiService.resolveMediaUrl(user.avatarUrl)!,
                        )
                        as ImageProvider
                  : null,
              child: user.avatarUrl == null || user.avatarUrl!.isEmpty
                  ? Text(
                      user.firstName.isNotEmpty ? user.firstName[0] : '?',
                      style: const TextStyle(fontSize: 24),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.fullName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(user.email, style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ),
            const Icon(Icons.shield, color: Colors.blue),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    int active = _rentals.where((r) => r.status == 'ACTIVE').length;
    int pending = _rentals.where((r) => r.status == 'PENDING').length;
    int drafts = _rentals.where((r) => r.status == 'DRAFT').length;

    return Row(
      children: [
        _buildStatCard(
          'Buildings',
          _buildings.length.toString(),
          Colors.purple,
        ),
        const SizedBox(width: 8),
        _buildStatCard('Active', active.toString(), Colors.green),
        const SizedBox(width: 8),
        _buildStatCard('Pending', pending.toString(), Colors.orange),
        const SizedBox(width: 8),
        _buildStatCard('Drafts', drafts.toString(), Colors.grey),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
        color: color.withOpacity(0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: color.withOpacity(0.8)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Landlord Dashboard')),
      body: _isLoading
          ? const Center(child: DwellyOrbitingLoader(size: 64))
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildProfileCard(),
                  const SizedBox(height: 16),
                  _buildStatsRow(),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Your Buildings',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add'),
                        onPressed: () async {
                          final result = await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const LandlordCreateBuildingPage(),
                            ),
                          );
                          if (result == true) {
                            _loadData();
                          }
                        },
                      ),
                    ],
                  ),
                  if (_buildings.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16.0),
                      child: Text(
                        'No buildings yet',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  else
                    SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _buildings.length,
                        itemBuilder: (context, index) {
                          final b = _buildings[index];
                          return GestureDetector(
                            onTap: () async {
                              final result = await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      LandlordEditBuildingPage(building: b),
                                ),
                              );
                              if (result == true) {
                                _loadData();
                              }
                            },
                            child: Card(
                              margin: const EdgeInsets.only(right: 12),
                              child: Container(
                                width: 150,
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      b['name'] ?? 'Unnamed',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${b['ward'] ?? ''}, ${b['county'] ?? ''}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Recent Rentals',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add'),
                        onPressed: () async {
                          final result = await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => LandlordCreateRentalPage(
                                buildings: _buildings,
                              ),
                            ),
                          );
                          if (result == true) {
                            _loadData();
                          }
                        },
                      ),
                    ],
                  ),
                  if (_rentals.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16.0),
                      child: Text(
                        'No rentals yet',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  else ...[
                    ..._rentals.take(_visibleRentalsLimit).map((r) {
                      Color statusColor = Colors.grey;
                      if (r.status == 'ACTIVE') statusColor = Colors.green;
                      if (r.status == 'PENDING') statusColor = Colors.orange;
                      if (r.status == 'REJECTED') statusColor = Colors.red;

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            image: r.imageUrls.isNotEmpty
                                ? DecorationImage(
                                    image: CachedNetworkImageProvider(
                                      ApiService.resolveMediaUrl(
                                        r.imageUrls.first,
                                      )!,
                                    ),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                            color: Colors.grey[200],
                          ),
                          child: r.imageUrls.isEmpty
                              ? const Icon(Icons.home, color: Colors.grey)
                              : null,
                        ),
                        title: Text(
                          '${r.bedrooms} Bed, ${r.propertyType}',
                          maxLines: 1,
                        ),
                        subtitle: Text(
                          'KES ${r.price.toStringAsFixed(0)} • ${r.areaName ?? r.ward}',
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            r.status ?? 'UNKNOWN',
                            style: TextStyle(
                              fontSize: 10,
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        onTap: () async {
                          final result = await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => LandlordEditRentalPage(
                                rental: r,
                                buildings: _buildings,
                              ),
                            ),
                          );
                          if (result == true) {
                            _loadData();
                          }
                        },
                      );
                    }),
                    if (_rentals.length > _visibleRentalsLimit)
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _visibleRentalsLimit += 10;
                              });
                            },
                            icon: const Icon(Icons.expand_more),
                            label: Text(
                              'Show More Rentals (${_rentals.length - _visibleRentalsLimit} remaining)',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_visibleRentalsLimit > 10 && _rentals.length > 10)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Center(
                          child: TextButton(
                            onPressed: () {
                              setState(() {
                                _visibleRentalsLimit = 10;
                              });
                            },
                            child: const Text('Show Less'),
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 32),
                  const Text(
                    'For advanced property management (financials, tenants, full edits), please log in to the RealAdmin web portal.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
