class HealthResponse {
  const HealthResponse({
    required this.status,
    required this.version,
    required this.environment,
  });

  final String status;
  final String version;
  final String environment;

  factory HealthResponse.fromJson(Map<String, dynamic> json) {
    return HealthResponse(
      status: json['status'] as String,
      version: json['version'] as String,
      environment: json['environment'] as String,
    );
  }

  @override
  String toString() =>
      'HealthResponse(status: $status, version: $version, environment: $environment)';
}
