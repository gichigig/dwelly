import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/helpers_repository.dart';
import 'package:realestate/core/services/helper_job_service.dart';
import '../../../core/widgets/full_screen_image_avatar.dart';
import '../../../core/widgets/dwelly_orbiting_loader.dart';

class HelpersView extends ConsumerStatefulWidget {
  const HelpersView({super.key});

  @override
  ConsumerState<HelpersView> createState() => _HelpersViewState();
}

class _HelpersViewState extends ConsumerState<HelpersView> {
  String? _selectedCounty;

  final List<String> _counties = [
    'Nairobi', 'Mombasa', 'Kisumu', 'Nakuru', 'Kiambu', 'Machakos', 'Kajiado',
    // ... add more as needed
  ];

  @override
  Widget build(BuildContext context) {
    final helpersAsync = ref.watch(availableHelpersProvider(_selectedCounty));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: DropdownButtonFormField<String>(
            value: _selectedCounty,
            decoration: InputDecoration(
              labelText: 'Filter by County',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.location_city),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('All Counties')),
              ..._counties.map(
                (c) => DropdownMenuItem(value: c, child: Text(c)),
              ),
            ],
            onChanged: (val) => setState(() => _selectedCounty = val),
          ),
        ),
        Expanded(
          child: helpersAsync.when(
            data: (helpers) {
              if (helpers.isEmpty) {
                return const Center(
                  child: Text(
                    'No helpers available in this area yet.',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: helpers.length,
                itemBuilder: (context, index) {
                  final helper = helpers[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              FullScreenImageAvatar(
                                radius: 24,
                                backgroundColor: Theme.of(
                                  context,
                                ).primaryColor.withOpacity(0.1),
                                avatarUrl: helper.avatarUrl,
                                fallbackWidget: Text(
                                  helper.name[0],
                                  style: TextStyle(
                                    color: Theme.of(context).primaryColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      helper.name,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (helper.helperCoverageLevel == 'WARD' &&
                                        helper.helperWards != null &&
                                        helper.helperWards!.isNotEmpty)
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.location_on,
                                            size: 14,
                                            color: Colors.grey,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              'Wards: ${helper.helperWards!.join(', ')}',
                                              style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 12,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      )
                                    else if (helper.helperCoverageLevel ==
                                            'CONSTITUENCY' &&
                                        helper.helperConstituencies != null &&
                                        helper.helperConstituencies!.isNotEmpty)
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.location_on,
                                            size: 14,
                                            color: Colors.grey,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              'Constituencies: ${helper.helperConstituencies!.join(', ')}',
                                              style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 12,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      )
                                    else if (helper.helperCounty != null)
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.location_on,
                                            size: 14,
                                            color: Colors.grey,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            helper.helperCounty!,
                                            style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'KES ${helper.helperPrice.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () {
                                HelperJobService.redirectToRealAdminPayment(
                                  helperId: helper.id,
                                  amount: helper.helperPrice,
                                );
                              },
                              icon: const Icon(Icons.handshake),
                              label: const Text('Hire Helper'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: DwellyOrbitingLoader(size: 64)),
            error: (err, _) => Center(child: Text('Error: $err')),
          ),
        ),
      ],
    );
  }
}
