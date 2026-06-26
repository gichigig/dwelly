import 'package:flutter/material.dart';
import '../../features/landlord/services/landlord_service.dart';

class CreateGroupDialog extends StatefulWidget {
  const CreateGroupDialog({super.key});

  @override
  State<CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<CreateGroupDialog> {
  final _nameController = TextEditingController();
  bool _isLoading = true;
  List<dynamic> _buildings = [];
  String? _selectedBuildingId;

  @override
  void initState() {
    super.initState();
    _fetchBuildings();
  }

  Future<void> _fetchBuildings() async {
    try {
      final buildings = await LandlordService.getMyBuildings();
      if (mounted) {
        setState(() {
          _buildings = buildings;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          // If fetching fails, we just don't show the building dropdown
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create New Group'),
      content: _isLoading
          ? const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Group Name',
                    hintText: 'Enter group name',
                  ),
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                ),
                if (_buildings.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Link to Building (Optional)',
                      hintText: 'Select a building',
                    ),
                    value: _selectedBuildingId,
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('None'),
                      ),
                      ..._buildings.map((b) => DropdownMenuItem<String>(
                            value: b['id'].toString(),
                            child: Text(b['name'] ?? 'Unnamed Building'),
                          )),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _selectedBuildingId = v;
                      });
                    },
                  ),
                ],
              ],
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isLoading
              ? null
              : () {
                  final name = _nameController.text.trim();
                  if (name.isEmpty) return;
                  
                  final result = <String, dynamic>{
                    'name': name,
                    'buildingId': _selectedBuildingId != null ? int.tryParse(_selectedBuildingId!) : null,
                  };
                  
                  Navigator.pop(context, result);
                },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
