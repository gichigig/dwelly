import 'package:flutter/material.dart';
import 'package:realestate/core/models/helper_job.dart';
import 'package:realestate/core/services/helper_job_service.dart';
import 'package:realestate/core/widgets/dwelly_orbiting_loader.dart';

class ClientJobsPage extends StatefulWidget {
  const ClientJobsPage({super.key});

  @override
  State<ClientJobsPage> createState() => _ClientJobsPageState();
}

class _ClientJobsPageState extends State<ClientJobsPage> {
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  List<HelperJob> _jobs = [];

  int _page = 0;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadJobs();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _loadJobs(loadMore: true);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadJobs({bool loadMore = false}) async {
    if (loadMore && (_isLoadingMore || !_hasMore)) return;

    if (loadMore) {
      setState(() => _isLoadingMore = true);
    } else {
      setState(() {
        _isLoading = true;
        _error = null;
        _page = 0;
        _hasMore = true;
      });
    }

    try {
      final jobs = await HelperJobService.getClientJobs(page: _page);
      if (mounted) {
        setState(() {
          if (loadMore) {
            _jobs.addAll(jobs);
            _isLoadingMore = false;
          } else {
            _jobs = jobs;
            _isLoading = false;
          }
          if (jobs.isEmpty || jobs.length < 20) _hasMore = false;
          if (jobs.isNotEmpty) _page++;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (loadMore) {
            _isLoadingMore = false;
          } else {
            _error = e.toString();
            _isLoading = false;
          }
        });
      }
    }
  }

  Future<void> _updateJobStatus(int jobId, String action) async {
    try {
      if (action == 'approve') {
        await HelperJobService.approveJob(jobId);
      } else {
        await HelperJobService.disputeJob(jobId);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Job $action successful'),
          backgroundColor: Colors.green,
        ),
      );
      _loadJobs();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Helper Jobs')),
      body: _isLoading
          ? const Center(child: DwellyOrbitingLoader(size: 64))
          : _error != null
          ? Center(
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          : _jobs.isEmpty
          ? const Center(child: Text('You have not hired any helpers yet.'))
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _jobs.length + (_isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _jobs.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Center(child: DwellyOrbitingLoader()),
                  );
                }
                final job = _jobs[index];
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
                            Text(
                              'Helper: ${job.helper.fullName}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Chip(
                              label: Text(
                                job.status.value,
                                style: const TextStyle(fontSize: 12),
                              ),
                              backgroundColor: job.status.value == 'ACTIVE'
                                  ? Colors.green.shade100
                                  : Colors.grey.shade200,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Amount: KES ${job.amount.toStringAsFixed(0)}'),
                        if (job.description != null &&
                            job.description!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('Description: ${job.description}'),
                        ],
                        const SizedBox(height: 16),
                        if (job.status.value == 'ACTIVE')
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () =>
                                      _updateJobStatus(job.id, 'dispute'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                  ),
                                  child: const Text('Dispute'),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () =>
                                      _updateJobStatus(job.id, 'approve'),
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
            ),
    );
  }
}
