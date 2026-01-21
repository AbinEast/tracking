import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'models.dart';
import 'firebase_helper.dart';

class HistoryPlaybackScreen extends StatefulWidget {
  const HistoryPlaybackScreen({super.key});

  @override
  State<HistoryPlaybackScreen> createState() => _HistoryPlaybackScreenState();
}

class _HistoryPlaybackScreenState extends State<HistoryPlaybackScreen> {
  final Completer<GoogleMapController> _controller =
      Completer<GoogleMapController>();
  final FirebaseHelper _firebaseHelper = FirebaseHelper();

  // Default location (Tugu Jogja)
  static const LatLng _center = LatLng(-7.782928, 110.367067);
  static const CameraPosition _kDefaultPosition = CameraPosition(
    target: _center,
    zoom: 14.4746,
  );

  // Data
  List<VehicleData> _historyData = [];
  DateTime _selectedDate = DateTime.now();

  // Playback State
  int _currentIndex = 0;
  bool _isPlaying = false;
  Timer? _playbackTimer;

  // Map Elements
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    _loadHistoryData();
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadHistoryData() async {
    final data = await _firebaseHelper.getHistoryByDate(_selectedDate);
    setState(() {
      _historyData = data;
      _currentIndex = 0;
      _isPlaying = false;
      _playbackTimer?.cancel();
    });
    _updateMapDisplay();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadHistoryData();
    }
  }

  void _updateMapDisplay() {
    if (_historyData.isEmpty) {
      setState(() {
        _markers = {};
        _polylines = {};
      });
      return;
    }

    // Full route (gray) - as background
    final fullRoutePoints = _historyData.map((d) => d.position).toList();

    // Current position marker
    final currentData = _historyData[_currentIndex];

    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('vehicle'),
          position: currentData.position,
          rotation: currentData.heading,
          infoWindow: InfoWindow(
            title: 'Vehicle',
            snippet: '${currentData.speed.toStringAsFixed(1)} km/h',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      };

      // Build polylines with speed heatmap
      Set<Polyline> polylines = {
        // Full route - gray background
        Polyline(
          polylineId: const PolylineId('full_route'),
          points: fullRoutePoints,
          color: Colors.grey.shade300,
          width: 4,
        ),
      };

      // Add traveled segments with speed-based colors
      for (int i = 0; i < _currentIndex && i < _historyData.length - 1; i++) {
        final startPoint = _historyData[i];
        final endPoint = _historyData[i + 1];
        final color = _getSpeedColor(startPoint.speed);

        polylines.add(
          Polyline(
            polylineId: PolylineId('traveled_$i'),
            points: [startPoint.position, endPoint.position],
            color: color,
            width: 6,
          ),
        );
      }

      _polylines = polylines;
    });

    _animateCameraToCurrentPosition();
  }

  // Get color based on speed for heatmap
  // Red: Stopped/Slow (< 10 km/h)
  // Orange: Medium (10-40 km/h)
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

  Future<void> _animateCameraToCurrentPosition() async {
    if (_historyData.isEmpty || !_controller.isCompleted) return;

    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(
      CameraUpdate.newLatLng(_historyData[_currentIndex].position),
    );
  }

  void _togglePlayback() {
    if (_historyData.isEmpty) return;

    setState(() {
      _isPlaying = !_isPlaying;
    });

    if (_isPlaying) {
      // Reset to beginning if at end
      if (_currentIndex >= _historyData.length - 1) {
        _currentIndex = 0;
      }
      _startPlayback();
    } else {
      _playbackTimer?.cancel();
    }
  }

  void _startPlayback() {
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_currentIndex < _historyData.length - 1) {
        setState(() {
          _currentIndex++;
        });
        _updateMapDisplay();
      } else {
        // End of playback
        timer.cancel();
        setState(() {
          _isPlaying = false;
        });
      }
    });
  }

  void _onSliderChanged(double value) {
    setState(() {
      _currentIndex = value.toInt();
      _isPlaying = false;
      _playbackTimer?.cancel();
    });
    _updateMapDisplay();
  }

  String _formatTimestamp(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History Playback'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          TextButton.icon(
            onPressed: _selectDate,
            icon: const Icon(Icons.calendar_today),
            label: Text(_formatDate(_selectedDate)),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: _kDefaultPosition,
            onMapCreated: (GoogleMapController controller) {
              _controller.complete(controller);
              if (_historyData.isNotEmpty) {
                _animateCameraToCurrentPosition();
              }
            },
            markers: _markers,
            polylines: _polylines,
          ),

          // Info Card (top)
          if (_historyData.isNotEmpty)
            Positioned(top: 10, left: 10, right: 10, child: _buildInfoCard()),

          // No data message
          if (_historyData.isEmpty)
            Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.history, size: 48, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        'No data for ${_formatDate(_selectedDate)}',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _selectDate,
                        child: const Text('Select Another Date'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Playback Controls (bottom)
          if (_historyData.isNotEmpty)
            Positioned(
              bottom: 20,
              left: 10,
              right: 10,
              child: _buildPlaybackControls(),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    final currentData = _historyData[_currentIndex];
    return Card(
      color: const Color.fromRGBO(255, 255, 255, 0.95),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildInfoItem(
              'Time',
              _formatTimestamp(currentData.timestamp),
              Icons.access_time,
            ),
            _buildInfoItem(
              'Speed',
              '${currentData.speed.toStringAsFixed(1)} km/h',
              Icons.speed,
              currentData.speed > 80 ? Colors.red : Colors.black,
            ),
            _buildInfoItem(
              'Heading',
              '${currentData.heading.toStringAsFixed(0)}°',
              Icons.explore,
            ),
            _buildInfoItem(
              'Engine',
              currentData.isIgnitionOn ? 'ON' : 'OFF',
              Icons.settings_power,
              currentData.isIgnitionOn ? Colors.green : Colors.grey,
            ),
          ],
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildPlaybackControls() {
    final currentData = _historyData[_currentIndex];
    return Card(
      color: const Color.fromRGBO(255, 255, 255, 0.95),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Timestamp display
            Text(
              _formatTimestamp(currentData.timestamp),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // Slider
            Row(
              children: [
                Text(
                  _formatTimestamp(_historyData.first.timestamp),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Expanded(
                  child: Slider(
                    value: _currentIndex.toDouble(),
                    min: 0,
                    max: (_historyData.length - 1).toDouble(),
                    divisions: _historyData.length > 1
                        ? _historyData.length - 1
                        : 1,
                    onChanged: _onSliderChanged,
                  ),
                ),
                Text(
                  _formatTimestamp(_historyData.last.timestamp),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),

            // Play/Pause & Progress
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 48,
                  icon: Icon(
                    _isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                  ),
                  color: Theme.of(context).colorScheme.primary,
                  onPressed: _togglePlayback,
                ),
                const SizedBox(width: 16),
                Text(
                  '${_currentIndex + 1} / ${_historyData.length}',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
