import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:geolocator/geolocator.dart';
import 'models.dart';

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  static Database? _database;

  factory DBHelper() {
    return _instance;
  }

  DBHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'vehicle_tracker.db');
    return await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE vehicle_history(
        pk INTEGER PRIMARY KEY AUTOINCREMENT,
        id TEXT,
        latitude REAL,
        longitude REAL,
        speed REAL,
        heading REAL,
        timestamp TEXT,
        isIgnitionOn INTEGER,
        batteryLevel INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE events(
        pk INTEGER PRIMARY KEY AUTOINCREMENT,
        assetId TEXT,
        eventType TEXT,
        timestamp TEXT,
        latitude REAL,
        longitude REAL,
        details TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE fleet_stats(
        pk INTEGER PRIMARY KEY AUTOINCREMENT,
        vehicleId TEXT UNIQUE,
        totalOdometer REAL DEFAULT 0,
        lastServiceOdometer REAL DEFAULT 0,
        lastServiceDate TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS events(
          pk INTEGER PRIMARY KEY AUTOINCREMENT,
          assetId TEXT,
          eventType TEXT,
          timestamp TEXT,
          latitude REAL,
          longitude REAL,
          details TEXT
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS fleet_stats(
          pk INTEGER PRIMARY KEY AUTOINCREMENT,
          vehicleId TEXT UNIQUE,
          totalOdometer REAL DEFAULT 0,
          lastServiceOdometer REAL DEFAULT 0,
          lastServiceDate TEXT
        )
      ''');
    }
  }

  Future<void> insertData(VehicleData data) async {
    final db = await database;
    await db.insert(
      'vehicle_history',
      data.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<VehicleData>> getHistoryByDate(DateTime date) async {
    final db = await database;
    String dateStr = date.toIso8601String().split('T')[0];

    final List<Map<String, dynamic>> maps = await db.query(
      'vehicle_history',
      where: 'timestamp LIKE ?',
      whereArgs: ['$dateStr%'],
      orderBy: 'timestamp ASC',
    );

    return List.generate(maps.length, (i) {
      return VehicleData.fromMap(maps[i]);
    });
  }

  // Insert event for tracking violations
  Future<void> insertEvent(TrackingEvent event) async {
    final db = await database;
    await db.insert('events', {
      'assetId': event.assetId,
      'eventType': event.type.name,
      'timestamp': event.timestamp.toIso8601String(),
      'latitude': event.location.latitude,
      'longitude': event.location.longitude,
      'details': event.details.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Get events count by type for a specific date
  Future<Map<String, int>> getEventCountsByDate(DateTime date) async {
    final db = await database;
    String dateStr = date.toIso8601String().split('T')[0];

    final List<Map<String, dynamic>> maps = await db.rawQuery(
      '''
      SELECT eventType, COUNT(*) as count 
      FROM events 
      WHERE timestamp LIKE ? 
      GROUP BY eventType
    ''',
      ['$dateStr%'],
    );

    Map<String, int> counts = {};
    for (var row in maps) {
      counts[row['eventType']] = row['count'] as int;
    }
    return counts;
  }

  // Calculate daily statistics
  Future<DailyStats> getDailyStats(DateTime date) async {
    final history = await getHistoryByDate(date);
    final eventCounts = await getEventCountsByDate(date);

    double totalDistance = 0;
    Duration engineOnDuration = Duration.zero;
    DateTime? engineOnStart;

    for (int i = 0; i < history.length; i++) {
      final data = history[i];

      // Calculate distance
      if (i > 0) {
        final prev = history[i - 1];
        totalDistance += Geolocator.distanceBetween(
          prev.position.latitude,
          prev.position.longitude,
          data.position.latitude,
          data.position.longitude,
        );
      }

      // Calculate engine hours
      if (data.isIgnitionOn) {
        engineOnStart ??= data.timestamp;
      } else {
        if (engineOnStart != null) {
          engineOnDuration += data.timestamp.difference(engineOnStart);
          engineOnStart = null;
        }
      }
    }

    // If engine was still on at the end
    if (engineOnStart != null && history.isNotEmpty) {
      engineOnDuration += history.last.timestamp.difference(engineOnStart);
    }

    // Calculate driver score (100 - penalties)
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

  // Odometer management
  Future<double> getOdometer(String vehicleId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'fleet_stats',
      where: 'vehicleId = ?',
      whereArgs: [vehicleId],
    );

    if (maps.isEmpty) {
      await db.insert('fleet_stats', {
        'vehicleId': vehicleId,
        'totalOdometer': 0,
        'lastServiceOdometer': 0,
      });
      return 0;
    }

    return maps.first['totalOdometer'] as double;
  }

  Future<void> updateOdometer(String vehicleId, double distanceKm) async {
    final db = await database;
    final currentOdometer = await getOdometer(vehicleId);
    final newOdometer = currentOdometer + distanceKm;

    await db.update(
      'fleet_stats',
      {'totalOdometer': newOdometer},
      where: 'vehicleId = ?',
      whereArgs: [vehicleId],
    );
  }

  Future<double> getLastServiceOdometer(String vehicleId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'fleet_stats',
      where: 'vehicleId = ?',
      whereArgs: [vehicleId],
    );

    if (maps.isEmpty) return 0;
    return maps.first['lastServiceOdometer'] as double;
  }

  Future<void> recordService(String vehicleId) async {
    final db = await database;
    final currentOdometer = await getOdometer(vehicleId);

    await db.update(
      'fleet_stats',
      {
        'lastServiceOdometer': currentOdometer,
        'lastServiceDate': DateTime.now().toIso8601String(),
      },
      where: 'vehicleId = ?',
      whereArgs: [vehicleId],
    );
  }

  // Check if service is needed (every 5000 km)
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
}

// Data class for daily statistics
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
