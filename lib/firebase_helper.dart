import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'models.dart';

class FirebaseHelper {
  static final FirebaseHelper _instance = FirebaseHelper._internal();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  factory FirebaseHelper() {
    return _instance;
  }

  FirebaseHelper._internal();

  // Get current user ID
  String get _userId => FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';

  // User-specific collection references
  CollectionReference _userCollection(String collection) =>
      _firestore.collection('users').doc(_userId).collection(collection);

  CollectionReference get _vehicleHistory => _userCollection('vehicle_history');
  CollectionReference get _events => _userCollection('events');
  DocumentReference get _fleetStatsDoc => _firestore
      .collection('users')
      .doc(_userId)
      .collection('fleet_stats')
      .doc('data');
  CollectionReference get _profiles => _userCollection('profiles');

  // Insert vehicle data
  Future<void> insertData(VehicleData data) async {
    await _vehicleHistory.add({
      'id': data.id,
      'latitude': data.position.latitude,
      'longitude': data.position.longitude,
      'speed': data.speed,
      'heading': data.heading,
      'timestamp': data.timestamp.toIso8601String(),
      'isIgnitionOn': data.isIgnitionOn,
      'batteryLevel': data.batteryLevel,
    });
  }

  // Get history by date
  Future<List<VehicleData>> getHistoryByDate(DateTime date) async {
    String dateStr = date.toIso8601String().split('T')[0];

    final snapshot = await _vehicleHistory
        .where('timestamp', isGreaterThanOrEqualTo: dateStr)
        .where('timestamp', isLessThan: '${dateStr}T23:59:59')
        .orderBy('timestamp')
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return VehicleData(
        id: data['id'],
        position: LatLng(data['latitude'], data['longitude']),
        speed: data['speed'].toDouble(),
        heading: data['heading'].toDouble(),
        timestamp: DateTime.parse(data['timestamp']),
        isIgnitionOn: data['isIgnitionOn'],
        batteryLevel: data['batteryLevel'],
      );
    }).toList();
  }

  // Insert event
  Future<void> insertEvent(TrackingEvent event) async {
    await _events.add({
      'assetId': event.assetId,
      'eventType': event.type.name,
      'timestamp': event.timestamp.toIso8601String(),
      'latitude': event.location.latitude,
      'longitude': event.location.longitude,
      'details': event.details.toString(),
    });
  }

  // Get events count by date
  Future<Map<String, int>> getEventCountsByDate(DateTime date) async {
    String dateStr = date.toIso8601String().split('T')[0];

    final snapshot = await _events
        .where('timestamp', isGreaterThanOrEqualTo: dateStr)
        .where('timestamp', isLessThan: '${dateStr}T23:59:59')
        .get();

    Map<String, int> counts = {};
    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      String eventType = data['eventType'];
      counts[eventType] = (counts[eventType] ?? 0) + 1;
    }
    return counts;
  }

  // Get daily stats
  Future<DailyStats> getDailyStats(DateTime date) async {
    final history = await getHistoryByDate(date);
    final eventCounts = await getEventCountsByDate(date);

    double totalDistance = 0;
    Duration engineOnDuration = Duration.zero;
    DateTime? engineOnStart;

    for (int i = 0; i < history.length; i++) {
      final data = history[i];

      if (i > 0) {
        final prev = history[i - 1];
        totalDistance += Geolocator.distanceBetween(
          prev.position.latitude,
          prev.position.longitude,
          data.position.latitude,
          data.position.longitude,
        );
      }

      if (data.isIgnitionOn) {
        engineOnStart ??= data.timestamp;
      } else {
        if (engineOnStart != null) {
          engineOnDuration += data.timestamp.difference(engineOnStart);
          engineOnStart = null;
        }
      }
    }

    if (engineOnStart != null && history.isNotEmpty) {
      engineOnDuration += history.last.timestamp.difference(engineOnStart);
    }

    int violations = 0;
    violations += eventCounts['overspeed'] ?? 0;
    violations += eventCounts['geofenceOut'] ?? 0;
    violations += eventCounts['harshBraking'] ?? 0;
    violations += eventCounts['harshAcceleration'] ?? 0;
    violations += eventCounts['harshCornering'] ?? 0;

    int driverScore = (100 - (violations * 5)).clamp(0, 100);

    return DailyStats(
      date: date,
      totalDistanceKm: totalDistance / 1000,
      engineHours: engineOnDuration,
      driverScore: driverScore,
      eventCounts: eventCounts,
    );
  }

  // Odometer management - now user-specific
  Future<double> getOdometer(String vehicleId) async {
    final doc = await _fleetStatsDoc.get();

    if (!doc.exists) {
      await _fleetStatsDoc.set({
        'totalOdometer': 0.0,
        'lastServiceOdometer': 0.0,
        'lastServiceDate': null,
      });
      return 0;
    }

    final data = doc.data() as Map<String, dynamic>;
    return (data['totalOdometer'] ?? 0).toDouble();
  }

  Future<void> updateOdometer(String vehicleId, double distanceKm) async {
    final currentOdometer = await getOdometer(vehicleId);
    final newOdometer = currentOdometer + distanceKm;

    await _fleetStatsDoc.update({'totalOdometer': newOdometer});
  }

  Future<double> getLastServiceOdometer(String vehicleId) async {
    final doc = await _fleetStatsDoc.get();
    if (!doc.exists) return 0;

    final data = doc.data() as Map<String, dynamic>;
    return (data['lastServiceOdometer'] ?? 0).toDouble();
  }

  Future<void> recordService(String vehicleId) async {
    final currentOdometer = await getOdometer(vehicleId);

    await _fleetStatsDoc.update({
      'lastServiceOdometer': currentOdometer,
      'lastServiceDate': DateTime.now().toIso8601String(),
    });
  }

  Future<bool> isServiceNeeded(String vehicleId) async {
    final currentOdometer = await getOdometer(vehicleId);
    final lastServiceOdometer = await getLastServiceOdometer(vehicleId);
    return (currentOdometer - lastServiceOdometer) >= 5000;
  }

  Future<double> getKmSinceLastService(String vehicleId) async {
    final currentOdometer = await getOdometer(vehicleId);
    final lastServiceOdometer = await getLastServiceOdometer(vehicleId);
    return currentOdometer - lastServiceOdometer;
  }

  // Profile management - user-specific
  Future<Map<String, dynamic>?> getProfile(String oderId) async {
    final doc = await _profiles.doc('vehicle').get();
    if (!doc.exists) return null;
    return doc.data() as Map<String, dynamic>;
  }

  Future<void> saveProfile(String oderId, Map<String, dynamic> profile) async {
    await _profiles.doc('vehicle').set(profile, SetOptions(merge: true));
  }

  Future<void> deleteProfile(String oderId) async {
    await _profiles.doc('vehicle').delete();
  }
}

// Keep DailyStats class for compatibility
class DailyStats {
  final DateTime date;
  final double totalDistanceKm;
  final Duration engineHours;
  final int driverScore;
  final Map<String, int> eventCounts;

  DailyStats({
    required this.date,
    required this.totalDistanceKm,
    required this.engineHours,
    required this.driverScore,
    required this.eventCounts,
  });
}
