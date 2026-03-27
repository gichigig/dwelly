import 'package:flutter/material.dart';
import '../data/kenya_locations.dart';

/// A location autocomplete widget for Kenya locations
/// Supports searching counties, constituencies, wards, and popular areas
class LocationAutocomplete extends StatefulWidget {
  final String? initialValue;
  final ValueChanged<LocationSearchResult>? onSelected;
  final ValueChanged<String>? onChanged;
  final String? labelText;
  final String? hintText;
  final bool required;
  final String? errorText;
  final InputDecoration? decoration;

  const LocationAutocomplete({
    super.key,
    this.initialValue,
    this.onSelected,
    this.onChanged,
    this.labelText,
    this.hintText = 'Search location...',
    this.required = false,
    this.errorText,
    this.decoration,
  });

  @override
  State<LocationAutocomplete> createState() => _LocationAutocompleteState();
}

class _LocationAutocompleteState extends State<LocationAutocomplete> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  List<LocationSearchResult> _results = [];
  int _highlightedIndex = -1;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode.addListener(_onFocusChange);
    _results = KenyaLocations.searchLocations('');
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _showOverlay();
    } else {
      _removeOverlay();
    }
  }

  void _showOverlay() {
    _removeOverlay();
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _search(String query) {
    setState(() {
      _results = KenyaLocations.searchLocations(query);
      _highlightedIndex = -1;
    });
    _overlayEntry?.markNeedsBuild();
    widget.onChanged?.call(query);
  }

  void _selectLocation(LocationSearchResult result) {
    _controller.text = result.displayName;
    widget.onSelected?.call(result);
    _focusNode.unfocus();
    _removeOverlay();
  }

  IconData _getTypeIcon(LocationType type) {
    switch (type) {
      case LocationType.county:
        return Icons.location_city;
      case LocationType.constituency:
        return Icons.pin_drop;
      case LocationType.ward:
        return Icons.holiday_village;
      case LocationType.area:
        return Icons.star;
    }
  }

  Color _getTypeColor(LocationType type) {
    switch (type) {
      case LocationType.county:
        return Colors.blue;
      case LocationType.constituency:
        return Colors.green;
      case LocationType.ward:
        return Colors.purple;
      case LocationType.area:
        return Colors.amber;
    }
  }

  String _getTypeLabel(LocationType type) {
    switch (type) {
      case LocationType.county:
        return 'County';
      case LocationType.constituency:
        return 'Constituency';
      case LocationType.ward:
        return 'Ward';
      case LocationType.area:
        return 'Area';
    }
  }

  OverlayEntry _createOverlayEntry() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    return OverlayEntry(
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        return Positioned(
          width: size.width,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, size.height + 4),
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 300),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withOpacity(0.7),
                  ),
                ),
                child: _results.isEmpty
                    ? _buildNoResults()
                    : _buildResultsList(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNoResults() {
    final query = _controller.text;
    final colorScheme = Theme.of(context).colorScheme;
    if (query.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(Icons.search_off, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(
            'No locations found for "$query"',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: _results.length + (_controller.text.isEmpty ? 1 : 0),
      itemBuilder: (context, index) {
        // Show header for popular locations
        if (_controller.text.isEmpty && index == 0) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.45),
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withOpacity(0.5),
                ),
              ),
            ),
            child: Text(
              'Popular Locations',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        final resultIndex = _controller.text.isEmpty ? index - 1 : index;
        if (resultIndex < 0 || resultIndex >= _results.length) {
          return const SizedBox.shrink();
        }

        final result = _results[resultIndex];
        final isHighlighted = resultIndex == _highlightedIndex;

        return InkWell(
          onTap: () => _selectLocation(result),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: isHighlighted ? colorScheme.primary.withOpacity(0.14) : null,
            child: Row(
              children: [
                Icon(
                  _getTypeIcon(result.type),
                  size: 24,
                  color: _getTypeColor(result.type),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.displayName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        result.subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getTypeColor(result.type).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _getTypeLabel(result.type),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: _getTypeColor(result.type),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        controller: _controller,
        focusNode: _focusNode,
        onChanged: _search,
        decoration:
            widget.decoration ??
            InputDecoration(
              labelText: widget.labelText,
              hintText: widget.hintText,
              errorText: widget.errorText,
              prefixIcon: const Icon(Icons.location_on_outlined),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _controller.clear();
                        _search('');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colorScheme.outlineVariant.withOpacity(0.8),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.primary, width: 2),
              ),
              filled: true,
              fillColor: theme.brightness == Brightness.dark
                  ? colorScheme.surfaceContainerHighest.withOpacity(0.55)
                  : Colors.grey.shade50,
            ),
        validator: widget.required
            ? (value) {
                if (value == null || value.isEmpty) {
                  return 'Please select a location';
                }
                return null;
              }
            : null,
      ),
    );
  }
}
