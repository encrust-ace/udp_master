enum CastMode { audio, video }

enum DeviceAction { add, update, delete }

enum DeviceType { strip, single, matrix }

extension DeviceTypeExtension on DeviceType {
  String get displayName {
    switch (this) {
      case DeviceType.strip:
        return 'LED Strip';
      case DeviceType.single:
        return 'Single';
      case DeviceType.matrix:
        return 'LED Matrix';
    }
  }
}

class LedDevice {
  final String name;
  final String ip;
  final int port;
  final int ledCount;
  String effect; // Mutable to allow fallback
  bool isEnabled;
  final DeviceType type;

  LedDevice({
    required this.name,
    required this.ip,
    required this.port,
    required this.ledCount,
    required this.effect,
    this.isEnabled = true,
    this.type = DeviceType.strip,
  });

  LedDevice copyWith({
    String? name,
    String? ip,
    int? port,
    int? ledCount,
    DeviceType? type,
    String? effect,
    bool? isEnabled,
  }) {

    return LedDevice(
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      ledCount: ledCount ?? this.ledCount,
      type: type ?? this.type,
      effect: effect ?? this.effect,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'ip': ip,
    'port': port,
    'ledCount': ledCount,
    'effect': effect,
    'isEnabled': isEnabled,
    'type': type.name,
  };

  factory LedDevice.fromJson(Map<String, dynamic> json) {
    return LedDevice(
      name: json['name'],
      ip: json['ip'],
      port: json['port'],
      ledCount: json['ledCount'],
      effect: json['effect'],
      isEnabled: json['isEnabled'],
      type: DeviceType.values.firstWhere(
        (e) => e.name == (json['type'] ?? DeviceType.strip.name),
        orElse: () => DeviceType.strip,
      ),
    );
  }
}
