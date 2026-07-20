import 'package:flutter/material.dart';
import 'package:realestate/core/models/user.dart';
import 'package:realestate/core/services/helper_service.dart';
import 'package:realestate/core/data/kenya_locations.dart';
import 'package:realestate/core/widgets/dwelly_orbiting_loader.dart';
import 'package:realestate/features/helper/presentation/helper_profile_page.dart';

class ServiceCategoryItem {
  final String name;
  final IconData icon;
  final String imageAsset;

  const ServiceCategoryItem(
    this.name,
    this.icon, [
    this.imageAsset = "assets/images/services/all_services.png",
  ]);
}

const List<ServiceCategoryItem> kServiceCategoriesList = [
  ServiceCategoryItem(
    "All",
    Icons.grid_view_rounded,
    "assets/images/services/all_services.png",
  ),
  ServiceCategoryItem(
    "House moving",
    Icons.home_work_rounded,
    "assets/images/services/moving.png",
  ),
  ServiceCategoryItem(
    "Gas delivery",
    Icons.gas_meter_rounded,
    "assets/images/services/gas_delivery.png",
  ),
  ServiceCategoryItem(
    "Water delivery",
    Icons.water_drop_rounded,
    "assets/images/services/water_delivery.png",
  ),
  ServiceCategoryItem(
    "Internet provider",
    Icons.wifi_rounded,
    "assets/images/services/all_services.png",
  ),
  ServiceCategoryItem(
    "Mama Fua",
    Icons.local_laundry_service_rounded,
    "assets/images/services/mama_fua.png",
  ),
  ServiceCategoryItem(
    "House cleaning",
    Icons.cleaning_services_rounded,
    "assets/images/services/house_cleaning.png",
  ),
  ServiceCategoryItem(
    "Food delivery",
    Icons.fastfood_rounded,
    "assets/images/services/food_delivery.png",
  ),
  ServiceCategoryItem(
    "Grocery delivery",
    Icons.shopping_basket_rounded,
    "assets/images/services/grocery_delivery.png",
  ),
  ServiceCategoryItem(
    "Boda delivery",
    Icons.two_wheeler_rounded,
    "assets/images/services/boda_delivery.png",
  ),
  ServiceCategoryItem(
    "Parcel delivery",
    Icons.local_shipping_rounded,
    "assets/images/services/parcel_delivery.png",
  ),
  ServiceCategoryItem(
    "Plumber",
    Icons.plumbing_rounded,
    "assets/images/services/plumber.png",
  ),
  ServiceCategoryItem(
    "Electrician",
    Icons.electrical_services_rounded,
    "assets/images/services/electrician.png",
  ),
  ServiceCategoryItem(
    "Carpenter",
    Icons.construction_rounded,
    "assets/images/services/carpenter.png",
  ),
  ServiceCategoryItem(
    "Mobile mechanic",
    Icons.build_rounded,
    "assets/images/services/mechanic.png",
  ),
  ServiceCategoryItem(
    "Barber/Hairdresser at home",
    Icons.cut_rounded,
    "assets/images/services/barber.png",
  ),
  ServiceCategoryItem(
    "Babysitter",
    Icons.child_care_rounded,
    "assets/images/services/babysitter.png",
  ),
];

class ServicesListPage extends StatefulWidget {
  final String? initialCategory;

  const ServicesListPage({super.key, this.initialCategory});

  @override
  State<ServicesListPage> createState() => _ServicesListPageState();
}

class _ServicesListPageState extends State<ServicesListPage> {
  bool _isLoading = true;
  String? _error;
  List<User> _providers = [];
  late String _selectedCategory;
  String? _selectedCounty;
  int _visibleLimit = 10;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory ?? "All";
    _loadProviders();
  }

  Future<void> _loadProviders() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _visibleLimit = 10;
    });

    try {
      final categoryParam = _selectedCategory == "All"
          ? null
          : _selectedCategory;
      final providers = await HelperService.getAvailableHelpers(
        county: _selectedCounty,
        category: categoryParam,
      );
      if (mounted) {
        setState(() {
          _providers = providers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Specialized Services'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Category Filter Bar
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: kServiceCategoriesList.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = kServiceCategoriesList[index];
                final isSelected = _selectedCategory == item.name;
                return ChoiceChip(
                  label: Text(
                    item.name,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : theme.textTheme.bodyMedium?.color,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: theme.colorScheme.primary,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  onSelected: (selected) {
                    if (selected && _selectedCategory != item.name) {
                      setState(() {
                        _selectedCategory = item.name;
                      });
                      _loadProviders();
                    }
                  },
                );
              },
            ),
          ),

          // County Filter
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: DropdownButtonFormField<String>(
              initialValue: _selectedCounty,
              decoration: InputDecoration(
                labelText: 'Filter by County',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                prefixIcon: const Icon(Icons.location_on_outlined),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('All Kenya Counties'),
                ),
                ...KenyaLocations.counties.map((county) {
                  return DropdownMenuItem(value: county, child: Text(county));
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedCounty = value;
                });
                _loadProviders();
              },
            ),
          ),

          // Providers List
          Expanded(
            child: _isLoading
                ? const Center(child: DwellyOrbitingLoader(size: 64))
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Error: $_error',
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _loadProviders,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _providers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.support_agent_rounded,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No service providers found for "$_selectedCategory".',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try changing your county or selecting a different category.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadProviders,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      itemCount: _providers.length > _visibleLimit
                          ? _visibleLimit + 1
                          : _providers.length,
                      itemBuilder: (context, index) {
                        if (index == _visibleLimit) {
                          final remaining = _providers.length - _visibleLimit;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (remaining > 0)
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        _visibleLimit += 10;
                                      });
                                    },
                                    icon: const Icon(Icons.expand_more),
                                    label: Text(
                                      'Show More Services ($remaining remaining)',
                                    ),
                                  ),
                                if (_visibleLimit > 10) ...[
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        _visibleLimit = 10;
                                      });
                                    },
                                    icon: const Icon(Icons.expand_less),
                                    label: const Text('Show Less'),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }
                        final provider = _providers[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => HelperProfilePage(
                                    helperId: provider.id!,
                                    helperName: provider.firstName,
                                  ),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 30,
                                    backgroundColor:
                                        theme.colorScheme.primaryContainer,
                                    backgroundImage:
                                        provider.avatarUrl != null &&
                                            provider.avatarUrl!.isNotEmpty
                                        ? NetworkImage(provider.avatarUrl!)
                                        : null,
                                    child:
                                        provider.avatarUrl == null ||
                                            provider.avatarUrl!.isEmpty
                                        ? Text(
                                            provider.firstName.isNotEmpty
                                                ? provider.firstName[0]
                                                      .toUpperCase()
                                                : '?',
                                            style: TextStyle(
                                              color: theme
                                                  .colorScheme
                                                  .onPrimaryContainer,
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                provider.fullName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme
                                                .colorScheme
                                                .secondaryContainer,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            provider.serviceCategory ??
                                                'Specialized Service',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: theme
                                                  .colorScheme
                                                  .onSecondaryContainer,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.location_on,
                                              size: 14,
                                              color: Colors.grey[600],
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              provider.helperCounty ?? 'Kenya',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              provider.helperPrice != null
                                                  ? 'KES ${provider.helperPrice!.toStringAsFixed(0)}'
                                                  : 'Rate Negotiable',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
