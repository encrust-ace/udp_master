// models.dart
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

  Segment({required this.id, required this.startIndex, required this.endIndex});

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
  final bool isEffectEnabled;
  final DeviceType type;
  final List<Segment> segments;

  LedDevice({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.ledCount,
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
    bool? isEffectEnabled,
    List<Segment> ?segments,
  }) {
    return LedDevice(
      id: id ?? this.id, // ID should not change
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      ledCount: ledCount ?? this.ledCount,
      type: type ?? this.type,
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
    'isEffectEnabled': isEffectEnabled,
    'type': type.name,
    'segments': segments.map((s) => s.toJson()).toList(),
  };

  factory LedDevice.fromJson(Map<String, dynamic> json) {
    return LedDevice(
      id: json['id'] as String,
      name: json['name'] as String,
      ip: json['ip'] as String,
      port: json['port'] as int,
      ledCount: json['ledCount'] as int,
      isEffectEnabled: json['isEffectEnabled'] as bool,
      type: DeviceType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => DeviceType.wled, // fallback if unknown
      ),
      segments: (json['segments'] as List<dynamic>)
          .map((e) => Segment.fromJson(e as Map<String, dynamic>))
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