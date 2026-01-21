import 'package:google_maps_flutter/google_maps_flutter.dart';

enum EventType {
  geofenceIn,
  geofenceOut,
  overspeed,
  idle,
  offline,
  tamper,
  harshBraking,
  harshAcceleration,
  harshCornering,
  crash,
}

class VehicleData {
  final String id;
  final LatLng position;
  final double speed; // in km/h
  final double heading;
  final DateTime timestamp;
  final bool isIgnitionOn;
  final int batteryLevel;

  VehicleData({
    required this.id,
    required this.position,
    required this.speed,
    required this.heading,
    required this.timestamp,
    required this.isIgnitionOn,
    required this.batteryLevel,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'speed': speed,
      'heading': heading,
      'timestamp': timestamp.toIso8601String(),
      'isIgnitionOn': isIgnitionOn ? 1 : 0,
      'batteryLevel': batteryLevel,
    };
  }

  factory VehicleData.fromMap(Map<String, dynamic> map) {
    return VehicleData(
      id: map['id'],
      position: LatLng(map['latitude'], map['longitude']),
      speed: map['speed'],
      heading: map['heading'],
      timestamp: DateTime.parse(map['timestamp']),
      isIgnitionOn: map['isIgnitionOn'] == 1,
      batteryLevel: map['batteryLevel'],
    );
  }
}

class TrackingEvent {
  final String assetId;
  final DateTime timestamp;
  final EventType type;
  final LatLng location;
  final Map<String, dynamic> details;

  TrackingEvent({
    required this.assetId,
    required this.timestamp,
    required this.type,
    required this.location,
    required this.details,
  });

  @override
  String toString() {
    return 'Event: ${type.name}, Time: $timestamp, Loc: $location, Details: $details';
  }
}
