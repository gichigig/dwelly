import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realestate/core/models/rental.dart';
import 'package:realestate/core/services/rental_service.dart';
import 'package:realestate/features/listings/presentation/rental_card.dart';
import 'package:realestate/core/errors/ui_error.dart';

class HashtagSearchPage extends ConsumerStatefulWidget {
  final String hashtag;

  const HashtagSearchPage({super.key, required this.hashtag});

  @override
  ConsumerState<HashtagSearchPage> createState() => _HashtagSearchPageState();
}

class _HashtagSearchPageState extends ConsumerState<HashtagSearchPage> {
  List<Rental> _rentals = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchHashtagRentals();
  }

  Future<void> _fetchHashtagRentals() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await RentalService.smartLocationSearch(
        nickname: '#${widget.hashtag.replaceFirst('#', '')}',
        page: 0,
        size: 50,
      );

      if (mounted) {
        setState(() {
          _rentals = result.rentals.rentals;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = userErrorMessage(e, fallbackMessage: 'Failed to load hashtag rentals.');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cleanHashtag = widget.hashtag.startsWith('#') ? widget.hashtag : '#${widget.hashtag}';

    return Scaffold(
      appBar: AppBar(
        title: Text(cleanHashtag),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchHashtagRentals,
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    if (_rentals.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('No listings found for ${widget.hashtag}'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _rentals.length,
      itemBuilder: (context, index) {
        final rental = _rentals[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: RentalCard(
            rental: rental,
            isSaved: false,
            onSaveToggle: () {}, // Handled internally by standard RentalCard
          ),
        );
      },
    );
  }
}
