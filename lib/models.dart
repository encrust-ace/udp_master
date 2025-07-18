import 'package:udp_master/led_effects.dart'; // Ensure this import is present

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
    String validatedEffectId = effect ?? this.effect;

    if (effect != null && availableEffects.isNotEmpty) {
      bool isNewEffectValid = availableEffects.any((e) => e.id == effect);
      if (!isNewEffectValid) {
        validatedEffectId =
            availableEffects.first.id; // Fallback for new effect
      }
    } else if (effect != null && availableEffects.isEmpty) {
      // If effects list is empty, we can't validate; keep what was passed or old.
      // Or assign a placeholder if that's preferable.
      validatedEffectId = effect; // Or consider a placeholder like "no-effects"
    }

    return LedDevice(
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      ledCount: ledCount ?? this.ledCount,
      type: type ?? this.type,
      effect: validatedEffectId, // Use validated or original
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
    String loadedEffectId;

    if (availableEffects.isNotEmpty) {
      loadedEffectId = json['effect'] ?? availableEffects.first.id;
      bool isValidEffect = availableEffects.any((e) => e.id == loadedEffectId);
      if (!isValidEffect) {
        loadedEffectId = availableEffects.first.id; // Fallback
      }
    } else {
      // No effects available to validate against or fallback to.
      // Use the effect from JSON if present, otherwise a placeholder.
      loadedEffectId = json['effect'] ?? 'no-effects-available';
    }

    return LedDevice(
      name: json['name'] ?? 'Unknown Device',
      ip: json['ip'] ?? '0.0.0.0',
      port: json['port'],
      ledCount: json['ledCount'] ?? 0,
      effect: loadedEffectId, // Use the validated/fallback ID
      isEnabled: json['isEnabled'] ?? true,
      type: DeviceType.values.firstWhere(
        (e) => e.name == (json['type'] ?? DeviceType.strip.name),
        orElse: () => DeviceType.strip,
      ),
    );
  }
}
