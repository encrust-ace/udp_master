enum CastMode { audio, video }

enum DeviceAction { add, update, delete }

enum DeviceType {
  wled('Wled', 21324),
  esphome('ESP Home', 21324),
  udp('UDP', 21324),
  wiz('Wiz', 38899),
  tuya('Tuya', 21324);

  const DeviceType(this.name, this.port);
  final String name;
  final int port;
}

class LedDevice {
  final String id;
  final String name;
  final String ip;
  final int port;
  final int ledCount;
  final String effect;
  final bool isEffectEnabled;
  final DeviceType type;

  LedDevice({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.ledCount,
    required this.effect,
    required this.isEffectEnabled,
    required this.type,
  });

  LedDevice copyWith({
    String? id,
    String? name,
    String? ip,
    int? port,
    int? ledCount,
    DeviceType? type,
    String? effect,
    bool? isEffectEnabled,
  }) {
    return LedDevice(
      id: id ?? this.id, // ID should not change
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      ledCount: ledCount ?? this.ledCount,
      type: type ?? this.type,
      effect: effect ?? this.effect,
      isEffectEnabled: isEffectEnabled ?? this.isEffectEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ip': ip,
    'port': port,
    'ledCount': ledCount,
    'effect': effect,
    'isEffectEnabled': isEffectEnabled,
    'type': type.name,
  };

  factory LedDevice.fromJson(Map<String, dynamic> json) {
    return LedDevice(
      id: json['id'],
      name: json['name'],
      ip: json['ip'],
      port: json['port'],
      ledCount: json['ledCount'],
      effect: json['effect'],
      isEffectEnabled: json['isEffectEnabled'],
      type: DeviceType.values.firstWhere((type) => type.name == json['type']),
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
