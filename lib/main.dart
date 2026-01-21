import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'models.dart';
import 'event_processor.dart';
import 'firebase_helper.dart';
import 'history_playback_screen.dart';
import 'fleet_summary_screen.dart';
import 'profile_screen.dart';
import 'login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const VehicleTrackerPage(),
    );
  }
}

// Auth wrapper to check login state
class VehicleTrackerPage extends StatelessWidget {
  const VehicleTrackerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show loading while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // If logged in, show main app
        if (snapshot.hasData) {
          return const VehicleTrackerHome();
        }

        // If not logged in, show login screen
        return const LoginScreen();
      },
    );
  }
}

class VehicleTrackerHome extends StatefulWidget {
  const VehicleTrackerHome({super.key});

  @override
  State<VehicleTrackerHome> createState() => _VehicleTrackerHomeState();
}

class _VehicleTrackerHomeState extends State<VehicleTrackerHome> {
  final Completer<GoogleMapController> _controller =
      Completer<GoogleMapController>();
  final EventProcessor _eventProcessor = EventProcessor();
  final Battery _battery = Battery();
  final FirebaseHelper _firebaseHelper = FirebaseHelper();

  // Default location (Tugu Jogja)
  static const LatLng _center = LatLng(-7.782928, 110.367067);
  static const CameraPosition _kDefaultPosition = CameraPosition(
    target: _center,
    zoom: 14.4746,
  );

  Set<Marker> _markers = {};
  final Set<Circle> _circles = {};
  Set<Polyline> _polylines = {};
  final List<LatLng> _routePoints = [];
  final List<VehicleData> _routeData = []; // Store full data for speed heatmap

  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<TrackingEvent>? _eventSubscription;

  VehicleData? _currentData;
  final List<TrackingEvent> _events = [];

  bool _isIgnitionOn = true; // Simulated ignition
  bool _isSimulating = false; // Flag for simulation mode
  int _simulationEventCount = 0; // Count events during simulation
  bool _simulationComplete = false; // Block events after simulation ends

  @override
  void initState() {
    super.initState();
    _setupInitialPosition(); // Set default position at Yogyakarta
    _setupGeofence();
    _setupEventListening();
    // Disabled real GPS tracking - using simulation mode only
    // _checkPermissionsAndStartTracking();
  }

  // Initialize with default position at Yogyakarta (Tugu Jogja)
  void _setupInitialPosition() {
    final initialData = VehicleData(
      id: 'vehicle_001',
      position: _center, // Tugu Jogja
      speed: 0,
      heading: 0,
      timestamp: DateTime.now(),
      isIgnitionOn: _isIgnitionOn,
      batteryLevel: 100,
    );

    _currentData = initialData;
    _routePoints.add(_center);
    _routeData.add(initialData);

    _markers = {
      Marker(
        markerId: const MarkerId('vehicle'),
        position: _center,
        infoWindow: const InfoWindow(
          title: 'Vehicle 001',
          snippet: 'Starting position',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      ),
    };
  }

  void _setupGeofence() {
    _circles.add(
      Circle(
        circleId: const CircleId('geofence_tugu'),
        center: _eventProcessor.geofenceCenter,
        radius: _eventProcessor.geofenceRadius,
        fillColor: const Color.fromRGBO(
          244,
          67,
          54,
          0.2,
        ), // Colors.red with opacity 0.2
        strokeColor: Colors.red,
        strokeWidth: 2,
      ),
    );
  }

  void _setupEventListening() {
    _eventSubscription = _eventProcessor.eventStream.listen((event) {
      if (!mounted) return;

      // Block all events after simulation completes
      if (_simulationComplete) {
        return;
      }

      // Limit events during simulation to max 3
      if (_isSimulating && _simulationEventCount >= 3) {
        return; // Skip events after 3
      }

      setState(() {
        _events.insert(0, event); // Add to top of list
        if (_isSimulating) {
          _simulationEventCount++;
        }
      });

      // Save event to Firebase for statistics
      _firebaseHelper.insertEvent(event);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('EVENT: ${event.type.name.toUpperCase()}'),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 2),
        ),
      );
    });

    // Check for service reminder on app start
    _checkServiceReminder();
  }

  Future<void> _checkServiceReminder() async {
    final serviceNeeded = await _firebaseHelper.isServiceNeeded('vehicle_001');
    if (serviceNeeded && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            '🔧 Waktunya Ganti Oli! Sudah lebih dari 5.000 km',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Lihat',
            textColor: Colors.white,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const FleetSummaryScreen(),
                ),
              );
            },
          ),
        ),
      );
    }
  }

  Future<void> _simulateRoute() async {
    // Check if engine is on
    if (!_isIgnitionOn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Tidak bisa simulasi - Engine OFF!'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Simplified route to trigger exactly 3 events:
    // 1. Overspeed (speed > 80 km/h)
    // 2. Geofence Exit (outside 500m radius from Tugu)
    // 3. Idle (speed = 0 for extended time)
    final List<Map<String, dynamic>> route = [
      // Start at Tugu Yogyakarta (inside geofence)
      {'lat': -7.782928, 'lng': 110.367067, 'speed': 0.0},
      {'lat': -7.782928, 'lng': 110.369000, 'speed': 40.0},
      // Overspeed event (speed > 80)
      {'lat': -7.782928, 'lng': 110.371000, 'speed': 95.0},
      {'lat': -7.782928, 'lng': 110.373000, 'speed': 95.0},
      // Exit geofence (> 500m from Tugu at 110.367067)
      {'lat': -7.782928, 'lng': 110.375000, 'speed': 50.0},
      {'lat': -7.782928, 'lng': 110.377000, 'speed': 30.0},
      // Slow down and stop (Idle event)
      {'lat': -7.782928, 'lng': 110.378500, 'speed': 0.0},
      {'lat': -7.782928, 'lng': 110.378500, 'speed': 0.0},
      {'lat': -7.782928, 'lng': 110.378500, 'speed': 0.0},
    ];

    // Clear previous events and start simulation mode
    setState(() {
      _events.clear();
      _isSimulating = true;
      _simulationEventCount = 0;
      _simulationComplete = false; // Reset flag
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Starting Route Simulation...')),
    );

    for (var point in route) {
      if (!mounted) break;

      _processPositionUpdate(
        Position(
          latitude: point['lat'],
          longitude: point['lng'],
          timestamp: DateTime.now(),
          accuracy: 5,
          altitude: 0,
          heading: 180,
          speed: (point['speed'] as double) / 3.6,
          speedAccuracy: 0,
          altitudeAccuracy: 0,
          headingAccuracy: 0,
          isMocked: true,
        ),
      );

      await Future.delayed(const Duration(seconds: 2));
    }

    // End simulation mode and block future events
    setState(() {
      _isSimulating = false;
      _simulationComplete = true; // Block all future events
    });

    if (mounted) {
      // Hide any pending event notifications
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      await Future.delayed(const Duration(milliseconds: 100));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Simulation Completed'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ignore: unused_element
  Future<void> _checkPermissionsAndStartTracking() async {
    final status = await Permission.location.request();
    if (status.isGranted) {
      _startTracking();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required.')),
        );
      }
    }
  }

  void _startTracking() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    _positionStreamSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
            _processPositionUpdate(position);
          },
        );
  }

  Future<void> _processPositionUpdate(Position position) async {
    int batteryLevel = await _battery.batteryLevel;

    // Create VehicleData object
    final data = VehicleData(
      id: 'vehicle_001',
      position: LatLng(position.latitude, position.longitude),
      speed: (position.speed * 3.6), // convert m/s to km/h
      heading: position.heading,
      timestamp: DateTime.now(),
      isIgnitionOn: _isIgnitionOn,
      batteryLevel: batteryLevel,
    );

    // Calculate distance for odometer
    if (_currentData != null) {
      final distanceM = Geolocator.distanceBetween(
        _currentData!.position.latitude,
        _currentData!.position.longitude,
        data.position.latitude,
        data.position.longitude,
      );
      final distanceKm = distanceM / 1000;
      if (distanceKm > 0.001) {
        // Only update if moved more than 1 meter
        _firebaseHelper.updateOdometer('vehicle_001', distanceKm);
      }
    }

    _eventProcessor.processData(data);
    _updateUI(data);

    // Save to Firebase for history playback
    _firebaseHelper.insertData(data);
  }

  void _updateUI(VehicleData data) async {
    if (!mounted) return;

    setState(() {
      _currentData = data;
      _routePoints.add(data.position);
      _routeData.add(data); // Store full data for heatmap

      _markers = {
        Marker(
          markerId: const MarkerId('vehicle'),
          position: data.position,
          rotation: data.heading,
          infoWindow: InfoWindow(
            title: 'Vehicle 001',
            snippet: '${data.speed.toStringAsFixed(1)} km/h',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      };

      // Build speed-based heatmap polylines
      _polylines = _buildSpeedPolylines(_routeData);
    });

    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newLatLng(data.position));
  }

  // Get color based on speed
  // Red: Stopped/Slow (< 10 km/h)
  // Yellow: Medium (10-40 km/h)
  // Green: Fast (> 40 km/h)
  Color _getSpeedColor(double speed) {
    if (speed < 10) {
      return Colors.red;
    } else if (speed < 40) {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }

  // Build polylines with colors based on speed
  Set<Polyline> _buildSpeedPolylines(List<VehicleData> routeData) {
    Set<Polyline> polylines = {};

    if (routeData.length < 2) {
      return polylines;
    }

    for (int i = 0; i < routeData.length - 1; i++) {
      final startPoint = routeData[i];
      final endPoint = routeData[i + 1];

      // Use the speed at the start point to determine segment color
      final color = _getSpeedColor(startPoint.speed);

      polylines.add(
        Polyline(
          polylineId: PolylineId('segment_$i'),
          points: [startPoint.position, endPoint.position],
          color: color,
          width: 6,
        ),
      );
    }

    return polylines;
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _eventSubscription?.cancel();
    _eventProcessor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tracker'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            tooltip: 'Profil Kendaraan',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.analytics),
            tooltip: 'Fleet Summary',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const FleetSummaryScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'History Playback',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const HistoryPlaybackScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.directions_car),
            tooltip: 'Simulate Drive Route',
            onPressed: _simulateRoute,
          ),
          IconButton(
            icon: Icon(_isIgnitionOn ? Icons.power : Icons.power_off),
            color: _isIgnitionOn ? Colors.green : Colors.red,
            tooltip: 'Toggle Ignition',
            onPressed: () {
              setState(() {
                _isIgnitionOn = !_isIgnitionOn;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Logout'),
                  content: const Text('Apakah Anda yakin ingin keluar?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Batal'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text(
                        'Logout',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await FirebaseAuth.instance.signOut();
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: _kDefaultPosition,
            onMapCreated: (GoogleMapController controller) {
              _controller.complete(controller);
            },
            onTap: (LatLng latLng) {
              // Simulation Mode: Teleport vehicle to tapped location
              _processPositionUpdate(
                Position(
                  latitude: latLng.latitude,
                  longitude: latLng.longitude,
                  timestamp: DateTime.now(),
                  accuracy: 0,
                  altitude: 0,
                  heading: 0,
                  speed: 40, // Simulate moving speed
                  speedAccuracy: 0,
                  altitudeAccuracy: 0,
                  headingAccuracy: 0,
                  isMocked: true,
                ),
              );

              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Simulation: Teleported to tapped location'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            markers: _markers,
            circles: _circles,
            polylines: _polylines,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
          ),
          _buildDashboard(),
          _buildEventLog(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          if (_currentData != null) {
            final GoogleMapController controller = await _controller.future;
            controller.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(target: _currentData!.position, zoom: 17),
              ),
            );
          }
        },
        child: const Icon(Icons.my_location),
      ),
    );
  }

  Widget _buildDashboard() {
    return Positioned(
      top: 10,
      left: 10,
      right: 10,
      child: Card(
        color: const Color.fromRGBO(
          255,
          255,
          255,
          0.9,
        ), // White with opacity 0.9
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildInfoItem(
                    'Speed',
                    '${_currentData?.speed.toStringAsFixed(1) ?? 0} km/h',
                    Icons.speed,
                    _currentData != null && _currentData!.speed > 80
                        ? Colors.red
                        : Colors.black,
                  ),
                  _buildInfoItem(
                    'Heading',
                    '${_currentData?.heading.toStringAsFixed(0) ?? 0}°',
                    Icons.explore,
                  ),
                  _buildInfoItem(
                    'Engine',
                    _isIgnitionOn ? 'ON' : 'OFF',
                    Icons.settings_power,
                    _isIgnitionOn ? Colors.green : Colors.grey,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Loc: ${_currentData?.position.latitude.toStringAsFixed(5) ?? 0}, ${_currentData?.position.longitude.toStringAsFixed(5) ?? 0}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem(
    String label,
    String value,
    IconData icon, [
    Color color = Colors.black,
  ]) {
    return Column(
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildEventLog() {
    return DraggableScrollableSheet(
      initialChildSize: 0.2,
      minChildSize: 0.1,
      maxChildSize: 0.5,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black26)],
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 8.0),
                child: Text(
                  'Event Logs',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _events.length,
                  itemBuilder: (context, index) {
                    final event = _events[index];
                    return ListTile(
                      leading: Icon(
                        _getEventIcon(event.type),
                        color: Colors.red,
                      ),
                      title: Text(event.type.name.toUpperCase()),
                      subtitle: Text(
                        '${event.timestamp.toString().split('.')[0]}\n${event.details}',
                      ),
                      isThreeLine: true,
                      dense: true,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _getEventIcon(EventType type) {
    switch (type) {
      case EventType.overspeed:
        return Icons.speed;
      case EventType.geofenceIn:
        return Icons.login;
      case EventType.geofenceOut:
        return Icons.logout;
      case EventType.idle:
        return Icons.timer;
      case EventType.offline:
        return Icons.signal_wifi_off;
      case EventType.tamper:
        return Icons.warning;
      case EventType.harshBraking:
        return Icons.front_loader;
      case EventType.harshAcceleration:
        return Icons.rocket_launch;
      case EventType.harshCornering:
        return Icons.turn_sharp_right;
      case EventType.crash:
        return Icons.car_crash;
    }
  }
}
