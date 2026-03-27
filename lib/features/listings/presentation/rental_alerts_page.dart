import 'package:flutter/material.dart';
import '../../../core/errors/ui_error.dart';
import '../../../core/services/rental_alert_service.dart';

class RentalAlertsPage extends StatefulWidget {
  const RentalAlertsPage({super.key});

  @override
  State<RentalAlertsPage> createState() => _RentalAlertsPageState();
}

class _RentalAlertsPageState extends State<RentalAlertsPage> {
  List<RentalAlert> _alerts = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final alerts = await RentalAlertService.getAlerts();
      setState(() {
        _alerts = alerts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = userErrorMessage(
          e,
          fallbackMessage: 'Failed to load rental alerts.',
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteAlert(int alertId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Alert'),
        content: const Text('Are you sure you want to delete this alert?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await RentalAlertService.deleteAlert(alertId);
      if (success) {
        setState(() {
          _alerts.removeWhere((a) => a.id == alertId);
        });
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Alert deleted')));
        }
      }
    }
  }

  Future<void> _toggleAlert(RentalAlert alert) async {
    try {
      final updated = await RentalAlertService.toggleAlert(
        alert.id,
        !alert.enabled,
      );
      setState(() {
        final index = _alerts.indexWhere((a) => a.id == alert.id);
        if (index != -1) {
          _alerts[index] = updated;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to toggle alert: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rental Alerts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateAlertDialog(context),
          ),
        ],
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
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(_error!),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadAlerts, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_alerts.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadAlerts,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _alerts.length,
        itemBuilder: (context, index) {
          final alert = _alerts[index];
          return _AlertCard(
            alert: alert,
            onToggle: () => _toggleAlert(alert),
            onEdit: () => _showEditAlertDialog(context, alert),
            onDelete: () => _deleteAlert(alert.id),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No Alerts Set',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create an alert to get notified when new rentals match your criteria',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showCreateAlertDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Create Alert'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateAlertDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _CreateAlertForm(
        onSuccess: (alert) {
          setState(() {
            _alerts.insert(0, alert);
          });
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Alert created successfully')),
          );
        },
      ),
    );
  }

  void _showEditAlertDialog(BuildContext context, RentalAlert alert) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _CreateAlertForm(
        existingAlert: alert,
        onSuccess: (updated) {
          setState(() {
            final index = _alerts.indexWhere((a) => a.id == alert.id);
            if (index != -1) {
              _alerts[index] = updated;
            }
          });
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Alert updated successfully')),
          );
        },
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final RentalAlert alert;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AlertCard({
    required this.alert,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: alert.alertType == AlertType.AREA
                        ? Colors.blue[50]
                        : Colors.purple[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    alert.alertType == AlertType.AREA
                        ? Icons.location_on
                        : Icons.apartment,
                    color: alert.alertType == AlertType.AREA
                        ? Colors.blue[600]
                        : Colors.purple[600],
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert.displayTitle,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        alert.displaySubtitle,
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Switch(value: alert.enabled, onChanged: (_) => onToggle()),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildBadge(
                  alert.alertType == AlertType.AREA
                      ? 'Area Alert'
                      : 'Vacancy Alert',
                  alert.alertType == AlertType.AREA
                      ? Colors.blue
                      : Colors.purple,
                ),
                if (alert.pushNotification) ...[
                  const SizedBox(width: 8),
                  _buildBadge('Push', Colors.green),
                ],
                if (alert.emailNotification) ...[
                  const SizedBox(width: 8),
                  _buildBadge('Email', Colors.orange),
                ],
                const Spacer(),
                Text(
                  '${alert.triggerCount} matches',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Edit'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[700],
                  ),
                ),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete, size: 18),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

class _CreateAlertForm extends StatefulWidget {
  final RentalAlert? existingAlert;
  final Function(RentalAlert) onSuccess;

  const _CreateAlertForm({this.existingAlert, required this.onSuccess});

  @override
  State<_CreateAlertForm> createState() => _CreateAlertFormState();
}

class _CreateAlertFormState extends State<_CreateAlertForm> {
  final _formKey = GlobalKey<FormState>();

  late AlertType _alertType;
  final _countyController = TextEditingController();
  final _constituencyController = TextEditingController();
  final _wardController = TextEditingController();
  final _buildingNameController = TextEditingController();
  final _buildingAddressController = TextEditingController();
  final _minPriceController = TextEditingController();
  final _maxPriceController = TextEditingController();

  int? _minBedrooms;
  int? _maxBedrooms;
  String? _propertyType;
  bool _pushNotification = true;
  bool _emailNotification = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingAlert != null) {
      final alert = widget.existingAlert!;
      _alertType = alert.alertType;
      _countyController.text = alert.county ?? '';
      _constituencyController.text = alert.constituency ?? '';
      _wardController.text = alert.ward ?? '';
      _buildingNameController.text = alert.buildingName ?? '';
      _buildingAddressController.text = alert.buildingAddress ?? '';
      _minPriceController.text = alert.minPrice?.toInt().toString() ?? '';
      _maxPriceController.text = alert.maxPrice?.toInt().toString() ?? '';
      _minBedrooms = alert.minBedrooms;
      _maxBedrooms = alert.maxBedrooms;
      _propertyType = alert.propertyType;
      _pushNotification = alert.pushNotification;
      _emailNotification = alert.emailNotification;
    } else {
      _alertType = AlertType.AREA;
    }
  }

  @override
  void dispose() {
    _countyController.dispose();
    _constituencyController.dispose();
    _wardController.dispose();
    _buildingNameController.dispose();
    _buildingAddressController.dispose();
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final request = CreateAlertRequest(
        alertType: _alertType,
        county:
            _alertType == AlertType.AREA && _countyController.text.isNotEmpty
            ? _countyController.text
            : null,
        constituency:
            _alertType == AlertType.AREA &&
                _constituencyController.text.isNotEmpty
            ? _constituencyController.text
            : null,
        ward: _alertType == AlertType.AREA && _wardController.text.isNotEmpty
            ? _wardController.text
            : null,
        buildingName:
            _alertType == AlertType.VACANCY &&
                _buildingNameController.text.isNotEmpty
            ? _buildingNameController.text
            : null,
        buildingAddress:
            _alertType == AlertType.VACANCY &&
                _buildingAddressController.text.isNotEmpty
            ? _buildingAddressController.text
            : null,
        minPrice: _minPriceController.text.isNotEmpty
            ? double.parse(_minPriceController.text)
            : null,
        maxPrice: _maxPriceController.text.isNotEmpty
            ? double.parse(_maxPriceController.text)
            : null,
        minBedrooms: _minBedrooms,
        maxBedrooms: _maxBedrooms,
        propertyType: _propertyType,
        pushNotification: _pushNotification,
        emailNotification: _emailNotification,
      );

      RentalAlert result;
      if (widget.existingAlert != null) {
        result = await RentalAlertService.updateAlert(
          widget.existingAlert!.id,
          request,
        );
      } else {
        result = await RentalAlertService.createAlert(request);
      }

      widget.onSuccess(result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.existingAlert != null ? 'Edit Alert' : 'Create Alert',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),

              // Alert Type
              const Text(
                'Alert Type',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              SegmentedButton<AlertType>(
                segments: const [
                  ButtonSegment(
                    value: AlertType.AREA,
                    label: Text('Area'),
                    icon: Icon(Icons.location_on),
                  ),
                  ButtonSegment(
                    value: AlertType.VACANCY,
                    label: Text('Building'),
                    icon: Icon(Icons.apartment),
                  ),
                ],
                selected: {_alertType},
                onSelectionChanged: (selected) {
                  setState(() => _alertType = selected.first);
                },
              ),
              const SizedBox(height: 16),

              // Location fields based on type
              if (_alertType == AlertType.AREA) ...[
                TextFormField(
                  controller: _countyController,
                  decoration: const InputDecoration(
                    labelText: 'County',
                    hintText: 'e.g., Kiambu',
                    prefixIcon: Icon(Icons.location_city),
                  ),
                  validator: (v) {
                    if (_countyController.text.isEmpty &&
                        _wardController.text.isEmpty) {
                      return 'Enter county or ward';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _constituencyController,
                  decoration: const InputDecoration(
                    labelText: 'Constituency (optional)',
                    hintText: 'e.g., Ruiru',
                    prefixIcon: Icon(Icons.map),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _wardController,
                  decoration: const InputDecoration(
                    labelText: 'Ward (optional)',
                    hintText: 'e.g., Biashara',
                    prefixIcon: Icon(Icons.location_on),
                  ),
                ),
              ] else ...[
                TextFormField(
                  controller: _buildingNameController,
                  decoration: const InputDecoration(
                    labelText: 'Building/Apartment Name',
                    hintText: 'e.g., Sunrise Apartments',
                    prefixIcon: Icon(Icons.apartment),
                  ),
                  validator: (v) {
                    if (_buildingNameController.text.isEmpty &&
                        _buildingAddressController.text.isEmpty) {
                      return 'Enter building name or address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _buildingAddressController,
                  decoration: const InputDecoration(
                    labelText: 'Building Address (optional)',
                    hintText: 'e.g., Moi Avenue',
                    prefixIcon: Icon(Icons.location_on),
                  ),
                ),
              ],

              const SizedBox(height: 16),
              const Text(
                'Price Range (optional)',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _minPriceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Min',
                        prefixText: 'KES ',
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _maxPriceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Max',
                        prefixText: 'KES ',
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Text(
                'Bedrooms (optional)',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      value: _minBedrooms,
                      decoration: const InputDecoration(labelText: 'Min'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Any')),
                        for (var i = 1; i <= 5; i++)
                          DropdownMenuItem(value: i, child: Text('$i')),
                      ],
                      onChanged: (v) => setState(() => _minBedrooms = v),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      value: _maxBedrooms,
                      decoration: const InputDecoration(labelText: 'Max'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Any')),
                        for (var i = 1; i <= 5; i++)
                          DropdownMenuItem(value: i, child: Text('$i')),
                      ],
                      onChanged: (v) => setState(() => _maxBedrooms = v),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Text(
                'Notification Preferences',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Push Notifications'),
                subtitle: const Text('Get notified on your device'),
                value: _pushNotification,
                onChanged: (v) => setState(() => _pushNotification = v),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text('Email Notifications'),
                subtitle: const Text('Get notified by email'),
                value: _emailNotification,
                onChanged: (v) => setState(() => _emailNotification = v),
                contentPadding: EdgeInsets.zero,
              ),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          widget.existingAlert != null
                              ? 'Update Alert'
                              : 'Create Alert',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
