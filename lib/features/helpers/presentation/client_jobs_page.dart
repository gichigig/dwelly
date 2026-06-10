import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:realestate/core/services/intercepted_client.dart' as http;
import '../../../core/config/env.dart';
import '../../auth/data/auth_repository.dart';

class ClientJob {
  final int id;
  final String helperName;
  final String? description;
  final double amount;
  final String status;
  final String createdAt;

  ClientJob({
    required this.id,
    required this.helperName,
    this.description,
    required this.amount,
    required this.status,
    required this.createdAt,
  });

  factory ClientJob.fromJson(Map<String, dynamic> json) {
    return ClientJob(
      id: json['id'],
      helperName: '${json['helper']['firstName']} ${json['helper']['lastName']}',
      description: json['description'],
      amount: (json['amount'] as num).toDouble(),
      status: json['status'],
      createdAt: json['createdAt'],
    );
  }
}

final clientJobsProvider = FutureProvider.autoDispose<List<ClientJob>>((ref) async {
  final token = await ref.watch(authRepositoryProvider).getToken();
  final response = await http.get(
    Uri.parse('${Env.apiBaseUrl}/api/helper-jobs/client'),
    headers: {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    },
  );

  if (response.statusCode == 200) {
    final List data = jsonDecode(response.body);
    return data.map((json) => ClientJob.fromJson(json)).toList();
  } else {
    throw Exception('Failed to load jobs');
  }
});

class ClientJobsPage extends ConsumerStatefulWidget {
  const ClientJobsPage({super.key});

  @override
  ConsumerState<ClientJobsPage> createState() => _ClientJobsPageState();
}

class _ClientJobsPageState extends ConsumerState<ClientJobsPage> {
  Future<void> _updateJobStatus(int jobId, String action) async {
    final token = await ref.read(authRepositoryProvider).getToken();
    final url = '${Env.apiBaseUrl}/api/helper-jobs/$jobId/$action';

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (mounted) {
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Job $action successful'),
            backgroundColor: Colors.green,
          ),
        );
        ref.invalidate(clientJobsProvider);
      } else {
        final body = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(body['error'] ?? 'Failed to $action job'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobsAsync = ref.watch(clientJobsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Helper Jobs')),
      body: jobsAsync.when(
        data: (jobs) {
          if (jobs.isEmpty) {
            return const Center(child: Text('You have not hired any helpers yet.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: jobs.length,
            itemBuilder: (context, index) {
              final job = jobs[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Helper: ${job.helperName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Chip(
                            label: Text(job.status, style: const TextStyle(fontSize: 12)),
                            backgroundColor: job.status == 'ACTIVE' ? Colors.green.shade100 : Colors.grey.shade200,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Amount: KES ${job.amount.toStringAsFixed(0)}'),
                      if (job.description != null) ...[
                        const SizedBox(height: 4),
                        Text('Description: ${job.description}'),
                      ],
                      const SizedBox(height: 16),
                      if (job.status == 'ACTIVE')
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _updateJobStatus(job.id, 'dispute'),
                                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                                child: const Text('Dispute'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: FilledButton(
                                onPressed: () => _updateJobStatus(job.id, 'approve'),
                                child: const Text('Approve'),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }
}
