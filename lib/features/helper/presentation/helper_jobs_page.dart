import 'package:flutter/material.dart';
import '../../../core/models/helper_job.dart';
import '../../../core/services/helper_job_service.dart';
import '../../../core/services/auth_service.dart';

class HelperJobsPage extends StatefulWidget {
  const HelperJobsPage({super.key});

  @override
  State<HelperJobsPage> createState() => _HelperJobsPageState();
}

class _HelperJobsPageState extends State<HelperJobsPage> {
  bool _isLoading = true;
  bool _isLoadingMoreClient = false;
  bool _isLoadingMoreHelper = false;
  String? _error;
  List<HelperJob> _clientJobs = [];
  List<HelperJob> _helperJobs = [];
  
  int _clientPage = 0;
  bool _clientHasMore = true;
  int _helperPage = 0;
  bool _helperHasMore = true;
  
  final ScrollController _clientScrollController = ScrollController();
  final ScrollController _helperScrollController = ScrollController();

  bool get _isHelper => AuthService.currentUser?.primaryRole == 'helper';

  @override
  void initState() {
    super.initState();
    _loadJobs();
    
    _clientScrollController.addListener(() {
      if (_clientScrollController.position.pixels >= _clientScrollController.position.maxScrollExtent - 200) {
        _loadClientJobs(loadMore: true);
      }
    });
    
    _helperScrollController.addListener(() {
      if (_helperScrollController.position.pixels >= _helperScrollController.position.maxScrollExtent - 200) {
        _loadHelperJobs(loadMore: true);
      }
    });
  }

  @override
  void dispose() {
    _clientScrollController.dispose();
    _helperScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadJobs() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await Future.wait([
        _loadClientJobs(),
        if (_isHelper) _loadHelperJobs(),
      ]);
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadClientJobs({bool loadMore = false}) async {
    if (loadMore && (_isLoadingMoreClient || !_clientHasMore)) return;
    
    if (loadMore) {
      setState(() => _isLoadingMoreClient = true);
    } else {
      _clientPage = 0;
      _clientHasMore = true;
    }

    try {
      final jobs = await HelperJobService.getClientJobs(page: _clientPage);
      if (mounted) {
        setState(() {
          if (loadMore) {
            _clientJobs.addAll(jobs);
            _isLoadingMoreClient = false;
          } else {
            _clientJobs = jobs;
          }
          if (jobs.isEmpty || jobs.length < 20) _clientHasMore = false;
          if (jobs.isNotEmpty) _clientPage++;
        });
      }
    } catch (e) {
      if (loadMore && mounted) setState(() => _isLoadingMoreClient = false);
      rethrow;
    }
  }

  Future<void> _loadHelperJobs({bool loadMore = false}) async {
    if (loadMore && (_isLoadingMoreHelper || !_helperHasMore)) return;
    
    if (loadMore) {
      setState(() => _isLoadingMoreHelper = true);
    } else {
      _helperPage = 0;
      _helperHasMore = true;
    }

    try {
      final jobs = await HelperJobService.getHelperJobs(page: _helperPage);
      if (mounted) {
        setState(() {
          if (loadMore) {
            _helperJobs.addAll(jobs);
            _isLoadingMoreHelper = false;
          } else {
            _helperJobs = jobs;
          }
          if (jobs.isEmpty || jobs.length < 20) _helperHasMore = false;
          if (jobs.isNotEmpty) _helperPage++;
        });
      }
    } catch (e) {
      if (loadMore && mounted) setState(() => _isLoadingMoreHelper = false);
      rethrow;
    }
  }

  Future<void> _approveJob(HelperJob job) async {
    try {
      await HelperJobService.approveJob(job.id);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Job approved and funds released!')));
      _loadJobs();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _disputeJob(HelperJob job) async {
    try {
      await HelperJobService.disputeJob(job.id);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Job disputed. We will review it.')));
      _loadJobs();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Widget _buildJobList(List<HelperJob> jobs, bool isClientView, ScrollController controller, bool isLoadingMore) {
    if (jobs.isEmpty) {
      return Center(
        child: Text(
          isClientView ? 'You have not hired any helpers yet.' : 'You have no helper jobs yet.',
          style: const TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.all(16),
      itemCount: jobs.length + (isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == jobs.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final job = jobs[index];
        final otherUser = isClientView ? job.helper : job.client;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isClientView ? 'Helper: ${otherUser.fullName}' : 'Client: ${otherUser.fullName}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(job.status),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        job.status.value,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Amount: KES ${job.amount.toStringAsFixed(2)}'),
                if (job.description != null && job.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Description: ${job.description}'),
                ],
                const SizedBox(height: 4),
                Text('Date: ${job.createdAt.toLocal().toString().split('.')[0]}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                if (isClientView && job.status == JobStatus.active) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _disputeJob(job),
                        child: const Text('Dispute', style: TextStyle(color: Colors.red)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => _approveJob(job),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                        child: const Text('Approve & Release Funds'),
                      ),
                    ],
                  )
                ]
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getStatusColor(JobStatus status) {
    switch (status) {
      case JobStatus.active: return Colors.blue;
      case JobStatus.completed: return Colors.green;
      case JobStatus.pendingPayment: return Colors.orange;
      case JobStatus.disputed: return Colors.red;
      case JobStatus.cancelled:
      case JobStatus.refunded: return Colors.grey;
    }
  }

  Widget _buildEarningsDashboard() {
    final user = AuthService.currentUser;
    final balance = user?.helperBalance ?? 0.0;
    final totalEarned = user?.helperTotalEarned ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.blueAccent, Colors.lightBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 10, offset: Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Earnings Dashboard', style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Available Balance', style: TextStyle(color: Colors.white, fontSize: 16)),
                  Text('KES ${balance.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
              ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Withdrawals coming soon!')));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('Withdraw'),
              ),
            ],
          ),
          const Divider(color: Colors.white30, height: 24),
          Text('Total Earned: KES ${totalEarned.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isHelper) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Hired Helpers')),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                : _buildJobList(_clientJobs, true, _clientScrollController, _isLoadingMoreClient),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Jobs'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Jobs I\'m Hiring'),
              Tab(text: 'Jobs I\'m Doing'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                : TabBarView(
                    children: [
                      _buildJobList(_clientJobs, true, _clientScrollController, _isLoadingMoreClient),
                      Column(
                        children: [
                          _buildEarningsDashboard(),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16.0),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Recent Jobs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          Expanded(child: _buildJobList(_helperJobs, false, _helperScrollController, _isLoadingMoreHelper)),
                        ],
                      ),
                    ],
                  ),
      ),
    );
  }
}
