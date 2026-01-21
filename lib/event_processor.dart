import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'models.dart';

class EventProcessor {
  final StreamController<TrackingEvent> _eventController =
      StreamController<TrackingEvent>.broadcast();
  Stream<TrackingEvent> get eventStream => _eventController.stream;

  // Config - GPS Events
  static const double overspeedThreshold = 80.0; // km/h
  static const int overspeedDurationThreshold = 5; // seconds

  static const double idleSpeedThreshold = 5.0; // km/h
  static const int idleDurationThreshold =
      10; // minutes (using seconds for demo: 10s)
  static const double idleDistanceTolerance = 20.0; // meters

  static const int offlineTimeout = 15; // minutes (using seconds for demo: 30s)

  // Config - Accelerometer Events (G-force thresholds)
  // 1G = 9.81 m/s²
  static const double gravityConstant = 9.81;
  static const double harshBrakingThreshold =
      -0.5; // G (negative = deceleration)
  static const double harshAccelerationThreshold = 0.4; // G
  static const double harshCorneringThreshold = 0.4; // G (lateral)
  static const double crashThreshold = 4.0; // G (total magnitude)
  static const double minSpeedForCornering = 20.0; // km/h

  // Cooldown periods to prevent event spam (in milliseconds)
  static const int eventCooldownMs = 3000;

  // State
  VehicleData? _lastData;

  // Overspeed State
  DateTime? _overspeedStartTime;
  double _maxSpeedInEpisode = 0.0;

  // Idle State
  DateTime? _idleStartTime;
  LatLng? _idleStartLocation;

  // Offline State
  Timer? _offlineTimer;

  // Geofence State
  final LatLng geofenceCenter = const LatLng(
    -7.782928,
    110.367067,
  ); // Tugu Jogja
  final double geofenceRadius = 500; // meters
  bool _wasInsideGeofence = true; // Assume start inside

  // Accelerometer State
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  DateTime? _lastHarshBrakingEvent;
  DateTime? _lastHarshAccelerationEvent;
  DateTime? _lastHarshCorneringEvent;
  DateTime? _lastCrashEvent;
  double _currentSpeed = 0.0; // Track current speed for accelerometer events

  // For crash detection: track if high G was detected
  bool _highGDetected = false;
  DateTime? _highGTimestamp;
  double _maxGForce = 0.0;

  EventProcessor() {
    _startAccelerometerMonitoring();
  }

  void _startAccelerometerMonitoring() {
    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      _processAccelerometerData(event);
    });
  }

  void _processAccelerometerData(AccelerometerEvent event) {
    if (_lastData == null) return;

    // Convert accelerometer readings to G-force
    // Note: Accelerometer includes gravity, so we need to consider device orientation
    // For simplicity, we'll use the raw values and assume:
    // - Y axis (event.y) = forward/backward (braking/acceleration)
    // - X axis (event.x) = left/right (cornering)
    // - Z axis (event.z) = up/down (includes gravity ~9.81 when stationary)

    final double forwardG = event.y / gravityConstant;
    final double lateralG = event.x / gravityConstant;

    // Calculate total G-force magnitude (excluding gravity)
    // Subtract 1G from total since gravity contributes ~1G when stationary
    final double totalMagnitude = sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    final double totalG = (totalMagnitude / gravityConstant);

    final now = DateTime.now();

    // Check Harsh Braking (strong negative forward G)
    if (forwardG < harshBrakingThreshold &&
        _canTriggerEvent(_lastHarshBrakingEvent, now)) {
      _lastHarshBrakingEvent = now;
      _eventController.add(
        TrackingEvent(
          assetId: _lastData!.id,
          timestamp: now,
          type: EventType.harshBraking,
          location: _lastData!.position,
          details: {
            'g_force': forwardG.toStringAsFixed(2),
            'speed_kmh': _currentSpeed.toStringAsFixed(1),
          },
        ),
      );
    }

    // Check Harsh Acceleration (strong positive forward G)
    if (forwardG > harshAccelerationThreshold &&
        _canTriggerEvent(_lastHarshAccelerationEvent, now)) {
      _lastHarshAccelerationEvent = now;
      _eventController.add(
        TrackingEvent(
          assetId: _lastData!.id,
          timestamp: now,
          type: EventType.harshAcceleration,
          location: _lastData!.position,
          details: {
            'g_force': forwardG.toStringAsFixed(2),
            'speed_kmh': _currentSpeed.toStringAsFixed(1),
          },
        ),
      );
    }

    // Check Harsh Cornering (high lateral G at speed)
    if (lateralG.abs() > harshCorneringThreshold &&
        _currentSpeed > minSpeedForCornering &&
        _canTriggerEvent(_lastHarshCorneringEvent, now)) {
      _lastHarshCorneringEvent = now;
      _eventController.add(
        TrackingEvent(
          assetId: _lastData!.id,
          timestamp: now,
          type: EventType.harshCornering,
          location: _lastData!.position,
          details: {
            'lateral_g': lateralG.toStringAsFixed(2),
            'speed_kmh': _currentSpeed.toStringAsFixed(1),
            'direction': lateralG > 0 ? 'right' : 'left',
          },
        ),
      );
    }

    // Check for Crash Detection
    // Step 1: Detect high G impact
    if (totalG > crashThreshold) {
      _highGDetected = true;
      _highGTimestamp = now;
      if (totalG > _maxGForce) {
        _maxGForce = totalG;
      }
    }

    // Step 2: If high G was detected and speed drops to near zero, trigger crash event
    if (_highGDetected &&
        _highGTimestamp != null &&
        _currentSpeed < 5.0 && // Speed dropped to near zero
        now.difference(_highGTimestamp!).inSeconds <
            5 && // Within 5 seconds of impact
        _canTriggerEvent(_lastCrashEvent, now)) {
      _lastCrashEvent = now;
      _eventController.add(
        TrackingEvent(
          assetId: _lastData!.id,
          timestamp: now,
          type: EventType.crash,
          location: _lastData!.position,
          details: {
            'max_g_force': _maxGForce.toStringAsFixed(2),
            'impact_time': _highGTimestamp.toString(),
            'current_speed': _currentSpeed.toStringAsFixed(1),
          },
        ),
      );

      // Reset crash detection state
      _highGDetected = false;
      _highGTimestamp = null;
      _maxGForce = 0.0;
    }

    // Reset high G detection if too much time passed without speed drop
    if (_highGDetected &&
        _highGTimestamp != null &&
        now.difference(_highGTimestamp!).inSeconds > 10) {
      _highGDetected = false;
      _highGTimestamp = null;
      _maxGForce = 0.0;
    }
  }

  bool _canTriggerEvent(DateTime? lastEventTime, DateTime now) {
    if (lastEventTime == null) return true;
    return now.difference(lastEventTime).inMilliseconds > eventCooldownMs;
  }

  void processData(VehicleData data) {
    _currentSpeed = data.speed; // Update current speed for accelerometer events

    _resetOfflineTimer(data);
    _checkOverspeed(data);
    _checkIdle(data);
    _checkGeofence(data);
    _checkTamper(data);

    _lastData = data;
  }

  void _resetOfflineTimer(VehicleData data) {
    _offlineTimer?.cancel();
    _offlineTimer = Timer(const Duration(minutes: offlineTimeout), () {
      _eventController.add(
        TrackingEvent(
          assetId: data.id,
          timestamp: DateTime.now(),
          type: EventType.offline,
          location: data.position,
          details: {
            'last_known_location': data.position.toString(),
            'duration_minutes': offlineTimeout,
          },
        ),
      );
    });
  }

  void _checkOverspeed(VehicleData data) {
    if (data.speed > overspeedThreshold) {
      if (_overspeedStartTime == null) {
        _overspeedStartTime = data.timestamp;
        _maxSpeedInEpisode = data.speed;
      } else {
        if (data.speed > _maxSpeedInEpisode) {
          _maxSpeedInEpisode = data.speed;
        }
      }
    } else {
      if (_overspeedStartTime != null) {
        final duration = data.timestamp
            .difference(_overspeedStartTime!)
            .inSeconds;
        if (duration >= overspeedDurationThreshold) {
          _eventController.add(
            TrackingEvent(
              assetId: data.id,
              timestamp: DateTime.now(),
              type: EventType.overspeed,
              location: data.position,
              details: {
                'ts_start': _overspeedStartTime.toString(),
                'ts_end': data.timestamp.toString(),
                'max_speed': _maxSpeedInEpisode,
                'threshold': overspeedThreshold,
              },
            ),
          );
        }
        _overspeedStartTime = null;
        _maxSpeedInEpisode = 0.0;
      }
    }
  }

  void _checkIdle(VehicleData data) {
    if (data.speed < idleSpeedThreshold && data.isIgnitionOn) {
      if (_idleStartTime == null) {
        _idleStartTime = data.timestamp;
        _idleStartLocation = data.position;
      } else {
        double distance = Geolocator.distanceBetween(
          _idleStartLocation!.latitude,
          _idleStartLocation!.longitude,
          data.position.latitude,
          data.position.longitude,
        );

        if (distance > idleDistanceTolerance) {
          _idleStartTime = data.timestamp;
          _idleStartLocation = data.position;
        }
      }
    } else {
      if (_idleStartTime != null) {
        final durationMinutes = data.timestamp
            .difference(_idleStartTime!)
            .inMinutes;
        if (durationMinutes >= 1) {
          _eventController.add(
            TrackingEvent(
              assetId: data.id,
              timestamp: DateTime.now(),
              type: EventType.idle,
              location: _idleStartLocation!,
              details: {
                'ts_start': _idleStartTime.toString(),
                'ts_end': data.timestamp.toString(),
                'duration_minutes': durationMinutes,
              },
            ),
          );
        }
        _idleStartTime = null;
        _idleStartLocation = null;
      }
    }
  }

  void _checkGeofence(VehicleData data) {
    double distance = Geolocator.distanceBetween(
      geofenceCenter.latitude,
      geofenceCenter.longitude,
      data.position.latitude,
      data.position.longitude,
    );

    bool isInside = distance <= geofenceRadius;

    if (_wasInsideGeofence && !isInside) {
      _eventController.add(
        TrackingEvent(
          assetId: data.id,
          timestamp: DateTime.now(),
          type: EventType.geofenceOut,
          location: data.position,
          details: {'type': 'geofence_out'},
        ),
      );
    } else if (!_wasInsideGeofence && isInside) {
      _eventController.add(
        TrackingEvent(
          assetId: data.id,
          timestamp: DateTime.now(),
          type: EventType.geofenceIn,
          location: data.position,
          details: {'type': 'geofence_in'},
        ),
      );
    }

    _wasInsideGeofence = isInside;
  }

  void _checkTamper(VehicleData data) {
    if (_lastData != null) {
      if (_lastData!.batteryLevel - data.batteryLevel > 20) {
        _eventController.add(
          TrackingEvent(
            assetId: data.id,
            timestamp: DateTime.now(),
            type: EventType.tamper,
            location: data.position,
            details: {
              'type': 'battery_drop',
              'drop': _lastData!.batteryLevel - data.batteryLevel,
            },
          ),
        );
      }
    }
  }

  void dispose() {
    _eventController.close();
    _offlineTimer?.cancel();
    _accelerometerSubscription?.cancel();
  }
}
