import 'package:realestate/core/models/user.dart';

enum JobStatus {
  pendingPayment('PENDING_PAYMENT'),
  active('ACTIVE'),
  completed('COMPLETED'),
  disputed('DISPUTED'),
  refunded('REFUNDED'),
  cancelled('CANCELLED');

  final String value;
  const JobStatus(this.value);

  factory JobStatus.fromString(String val) {
    return JobStatus.values.firstWhere(
      (e) => e.value == val,
      orElse: () => JobStatus.pendingPayment,
    );
  }
}

class HelperJob {
  final int id;
  final User helper;
  final User client;
  final double amount;
  final JobStatus status;
  final String? description;
  final DateTime createdAt;

  HelperJob({
    required this.id,
    required this.helper,
    required this.client,
    required this.amount,
    required this.status,
    this.description,
    required this.createdAt,
  });

  factory HelperJob.fromJson(Map<String, dynamic> json) {
    return HelperJob(
      id: json['id'] as int,
      helper: User.fromJson(json['helper'] as Map<String, dynamic>),
      client: User.fromJson(json['client'] as Map<String, dynamic>),
      amount: (json['amount'] as num).toDouble(),
      status: JobStatus.fromString(json['status'] as String),
      description: json['description'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
