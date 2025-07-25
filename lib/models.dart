enum CastMode { audio, video }

enum DeviceAction { add, update, delete }

enum DeviceType { wled, esphome, wiz, tuya }

extension DeviceTypeExtension on DeviceType {
  String get displayName {
    switch (this) {
      case DeviceType.wled:
        return 'Wled';
      case DeviceType.esphome:
        return 'ESP Home';
      case DeviceType.wiz:
        return 'Wiz';
      case DeviceType.tuya:
        return 'Tuya';
    }
  }
}

class LedDevice {
  final String name;
  final String ip;
  final int port;
  final int ledCount;
  final String effect;
  final bool isEnabled;
  final DeviceType type;

  LedDevice({
    required this.name,
    required this.ip,
    required this.port,
    required this.ledCount,
    required this.effect,
    required this.isEnabled,
    required this.type,
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
      type: DeviceType.values.firstWhere((e) => e.name == json['type']),
    );
  }
}

class LedEffect {
  final String id;
  final String name;
  final Map<String, Map<String, dynamic>> parameters;

  LedEffect({required this.id, required this.name, required this.parameters});

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'parameters': parameters,
  };

  factory LedEffect.fromJson(Map<String, dynamic> json) {
    return LedEffect(
      id: json['id'],
      name: json['name'],
      parameters: json['parameters'],
    );
  }

  LedEffect copyWith({
    String? id,
    String? name,
    Map<String, Map<String, dynamic>>? parameters,
  }) {
    return LedEffect(
      id: id ?? this.id,
      name: name ?? this.name,
      parameters: parameters ?? this.parameters,
    );
  }
}
