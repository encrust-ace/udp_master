enum DeviceAction { add, update, delete }

enum DeviceType {
  wled('Wled', 21324),
  wiz('Wiz', 38899),
  esphome('ESP Home', 21324);

  const DeviceType(this.label, this.port);
  final String label;
  final int port;
}

class Segment {
  final String id;
  final int startIndex;
  final int endIndex;

  Segment({
    required this.id,
    required this.startIndex,
    required this.endIndex,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'startIndex': startIndex,
    'endIndex': endIndex,
  };

  factory Segment.fromJson(Map<String, dynamic> json) {
    return Segment(
      id: json['id'] as String,
      startIndex: json['startIndex'] as int,
      endIndex: json['endIndex'] as int,
    );
  }

  Segment copyWith({
    String? id,
    String? name,
    int? startIndex,
    int? endIndex,
    LedDevice? device,
  }) {
    return Segment(
      id: id ?? this.id, 
      startIndex: startIndex ?? this.startIndex,
      endIndex: endIndex ?? this.endIndex,
    );
  }
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
  final List<Segment>? segments;

  LedDevice({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.ledCount,
    required this.effect,
    required this.isEffectEnabled,
    required this.type,
    required this.segments,
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
    List<Segment>? segments,
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
      segments: segments ?? this.segments,
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
      id: json['id'] as String,
      name: json['name'] as String,
      ip: json['ip'] as String,
      port: json['port'] as int,
      ledCount: json['ledCount'] as int,
      effect: json['effect'] as String,
      isEffectEnabled: json['isEffectEnabled'] as bool,
      type: DeviceType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => DeviceType.wled, // fallback if unknown
      ),
      segments: (json['segments'] as List<dynamic>?)
          ?.map((e) => Segment.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LedDevice && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
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
      id: json['id'] as String,
      name: json['name'] as String,
      parameters: (json['parameters'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)),
      ),
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

enum DisplayPosition { left, right, top, bottom }

class DisplaySide {
  final DisplayPosition position;
  final LedDevice? device;
  final int startIndex;
  final int endIndex;

  DisplaySide({
    required this.position,
    this.device,
    required this.startIndex,
    required this.endIndex,
  });

  Map<String, dynamic> toJson() => {
    'position': position.name,
    'device': device?.toJson(),
    'startIndex': startIndex,
    'endIndex': endIndex,
  };

  factory DisplaySide.fromJson(Map<String, dynamic> json) {
    return DisplaySide(
      position: DisplayPosition.values.firstWhere(
        (e) => e.name == json['position'],
      ),
      device: json['device'] != null
          ? LedDevice.fromJson(json['device'] as Map<String, dynamic>)
          : null,
      startIndex: json['startIndex'] as int,
      endIndex: json['endIndex'] as int,
    );
  }

  DisplaySide copyWith({LedDevice? device, int? startIndex, int? endIndex}) {
    return DisplaySide(
      position: position,
      device: device ?? this.device,
      startIndex: startIndex ?? this.startIndex,
      endIndex: endIndex ?? this.endIndex,
    );
  }
}
