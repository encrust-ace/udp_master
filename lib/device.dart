import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum DeviceAction {
  add,
  update,
  delete,
}

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
  String effect;
  bool isEnabled;
  final DeviceType type;

  LedDevice({
    required this.name,
    required this.ip,
    this.port = 21324,
    required this.ledCount,
    required this.effect,
    this.isEnabled = true,
    this.type = DeviceType.strip,
  });

  LedDevice copyWith({
    String? id,
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
      port: json['port'] ?? 21324,
      ledCount: json['ledCount'],
      effect: json['effect'] ?? 'linear-fill',
      isEnabled: json['isEnabled'] ?? true,
      type: DeviceType.values.firstWhere(
        (e) => e.name == (json['type'] ?? 'strip'),
        orElse: () => DeviceType.strip,
      ),
    );
  }
}

Future<void> updateDevices(List<LedDevice> devices) async {
  final prefs = await SharedPreferences.getInstance();
  final deviceList = devices.map((e) => json.encode(e.toJson())).toList();
  await prefs.setStringList('devices', deviceList);
}

Future<List<LedDevice>> loadDevices() async {
  final prefs = await SharedPreferences.getInstance();
  //   print(prefs.getKeys().fold<Map<String, Object?>>({}, (map, key) {
  //   map[key] = prefs.get(key);
  //   return map;
  // }));
  final deviceList = prefs.getStringList('devices') ?? [];
  return deviceList.map((e) => LedDevice.fromJson(json.decode(e))).toList();
}

Future<void> addNewDevice(LedDevice newDevice) async {
  final prefs = await SharedPreferences.getInstance();
  final deviceList = prefs.getStringList('devices') ?? [];
  final existingDevices = deviceList
      .map((e) => LedDevice.fromJson(json.decode(e)))
      .toList();
  existingDevices.add(newDevice);
  final updatedList = existingDevices
      .map((e) => json.encode(e.toJson()))
      .toList();
  await prefs.setStringList('devices', updatedList);
}
