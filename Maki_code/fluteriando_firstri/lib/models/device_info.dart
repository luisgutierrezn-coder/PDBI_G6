enum DeviceConnectionStatus {
  notConfigured,
  disconnected,
  connecting,
  connected,
  error,
}

class DeviceInfo {
  final String id;
  final String name;
  final String description;
  final String source;
  final DeviceConnectionStatus status;

  const DeviceInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.source,
    this.status = DeviceConnectionStatus.notConfigured,
  });

  DeviceInfo copyWith({
    String? name,
    String? description,
    String? source,
    DeviceConnectionStatus? status,
  }) {
    return DeviceInfo(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      source: source ?? this.source,
      status: status ?? this.status,
    );
  }
}