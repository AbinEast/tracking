import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_helper.dart';

class FleetSummaryScreen extends StatefulWidget {
  const FleetSummaryScreen({super.key});

  @override
  State<FleetSummaryScreen> createState() => _FleetSummaryScreenState();
}

class _FleetSummaryScreenState extends State<FleetSummaryScreen> {
  final FirebaseHelper _firebaseHelper = FirebaseHelper();

  DateTime _selectedDate = DateTime.now();
  DailyStats? _stats;
  double _totalOdometer = 0;
  double _kmSinceService = 0;
  bool _serviceNeeded = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);

    try {
      final stats = await _firebaseHelper.getDailyStats(_selectedDate);
      final odometer = await _firebaseHelper.getOdometer('vehicle_001');
      final kmSinceService = await _firebaseHelper.getKmSinceLastService(
        'vehicle_001',
      );
      final serviceNeeded = await _firebaseHelper.isServiceNeeded(
        'vehicle_001',
      );

      setState(() {
        _stats = stats;
        _totalOdometer = odometer;
        _kmSinceService = kmSinceService;
        _serviceNeeded = serviceNeeded;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
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
      _loadStats();
    }
  }

  Future<void> _recordService() async {
    await _firebaseHelper.recordService('vehicle_001');
    await _loadStats();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Service recorded successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return '${hours}h ${minutes}m';
  }

  Color _getScoreColor(int score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  Future<void> _printReport() async {
    final pdf = pw.Document();
    final score = _stats?.driverScore ?? 100;

    // Fetch profile data
    final userId = FirebaseAuth.instance.currentUser?.uid ?? 'default';
    final profile = await _firebaseHelper.getProfile(userId);
    final pemilik = profile?['pemilik'] ?? '-';
    final namaKendaraan = profile?['nama'] ?? '-';
    final noPolisi = profile?['noPolisi'] ?? '-';
    final merk = profile?['merk'] ?? '-';
    final model = profile?['model'] ?? '-';
    final tahun = profile?['tahun'] ?? '-';
    final warna = profile?['warna'] ?? '-';

    // Determine score color
    PdfColor scoreColor;
    String scoreText;
    if (score >= 80) {
      scoreColor = PdfColors.green;
      scoreText = 'Sangat Baik';
    } else if (score >= 60) {
      scoreColor = PdfColors.orange;
      scoreText = 'Perlu Perbaikan';
    } else {
      scoreColor = PdfColors.red;
      scoreText = 'Perlu Evaluasi';
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header with blue background
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(16),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.blue,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Column(
                  children: [
                    pw.Text(
                      'LAPORAN FLEET SUMMARY',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Vehicle Tracker System',
                      style: const pw.TextStyle(
                        fontSize: 12,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: pw.BorderRadius.circular(16),
                      ),
                      child: pw.Text(
                        'Tanggal: ${_formatDate(_selectedDate)}',
                        style: const pw.TextStyle(
                          fontSize: 12,
                          color: PdfColors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Vehicle Profile Section
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'DATA KENDARAAN',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'Pemilik: $pemilik',
                                style: const pw.TextStyle(fontSize: 10),
                              ),
                              pw.Text(
                                'Kendaraan: $namaKendaraan',
                                style: const pw.TextStyle(fontSize: 10),
                              ),
                              pw.Text(
                                'No. Polisi: $noPolisi',
                                style: pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'Merk/Model: $merk $model',
                                style: const pw.TextStyle(fontSize: 10),
                              ),
                              pw.Text(
                                'Tahun: $tahun',
                                style: const pw.TextStyle(fontSize: 10),
                              ),
                              pw.Text(
                                'Warna: $warna',
                                style: const pw.TextStyle(fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Stats Row
              pw.Row(
                children: [
                  // Distance Card
                  pw.Expanded(
                    child: _buildPdfCard(
                      'Jarak Tempuh',
                      '${_stats?.totalDistanceKm.toStringAsFixed(1) ?? "0"} km',
                      PdfColors.blue,
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  // Engine Hours Card
                  pw.Expanded(
                    child: _buildPdfCard(
                      'Mesin Menyala',
                      _formatDuration(_stats?.engineHours ?? Duration.zero),
                      PdfColors.green,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),

              // Driver Score Section
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  children: [
                    // Score Circle
                    pw.Container(
                      width: 60,
                      height: 60,
                      decoration: pw.BoxDecoration(
                        shape: pw.BoxShape.circle,
                        border: pw.Border.all(color: scoreColor, width: 4),
                      ),
                      child: pw.Center(
                        child: pw.Text(
                          '$score',
                          style: pw.TextStyle(
                            fontSize: 20,
                            fontWeight: pw.FontWeight.bold,
                            color: scoreColor,
                          ),
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 16),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Skor Pengemudi',
                            style: pw.TextStyle(
                              fontSize: 16,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            scoreText,
                            style: pw.TextStyle(color: scoreColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Odometer Section
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'ODOMETER',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 12),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'Total',
                              style: const pw.TextStyle(
                                fontSize: 10,
                                color: PdfColors.grey,
                              ),
                            ),
                            pw.Text(
                              '${_totalOdometer.toStringAsFixed(1)} km',
                              style: pw.TextStyle(
                                fontSize: 18,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.Text(
                              'Sejak Servis',
                              style: const pw.TextStyle(
                                fontSize: 10,
                                color: PdfColors.grey,
                              ),
                            ),
                            pw.Text(
                              '${_kmSinceService.toStringAsFixed(0)} km',
                              style: pw.TextStyle(
                                fontSize: 14,
                                color: _serviceNeeded
                                    ? PdfColors.orange
                                    : PdfColors.grey700,
                              ),
                            ),
                          ],
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: pw.BoxDecoration(
                            color: _serviceNeeded
                                ? PdfColors.orange
                                : PdfColors.green,
                            borderRadius: pw.BorderRadius.circular(4),
                          ),
                          child: pw.Text(
                            _serviceNeeded ? 'PERLU SERVIS' : 'OK',
                            style: const pw.TextStyle(
                              fontSize: 10,
                              color: PdfColors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Violations Section
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.red200),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        pw.Container(
                          width: 8,
                          height: 8,
                          decoration: const pw.BoxDecoration(
                            color: PdfColors.red,
                            shape: pw.BoxShape.circle,
                          ),
                        ),
                        pw.SizedBox(width: 8),
                        pw.Text(
                          'PELANGGARAN',
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 12),
                    if (_stats?.eventCounts.isEmpty ?? true)
                      pw.Container(
                        padding: const pw.EdgeInsets.all(12),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.green50,
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.center,
                          children: [
                            pw.Text(
                              '✓ Tidak ada pelanggaran',
                              style: const pw.TextStyle(
                                color: PdfColors.green700,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...(_stats!.eventCounts.entries.map(
                        (e) => pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 4),
                          child: pw.Row(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(_getEventLabel(e.key)),
                              pw.Container(
                                padding: const pw.EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: pw.BoxDecoration(
                                  color: PdfColors.red100,
                                  borderRadius: pw.BorderRadius.circular(12),
                                ),
                                child: pw.Text(
                                  '${e.value}x',
                                  style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.red,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )),
                  ],
                ),
              ),

              pw.Spacer(),
              // Footer
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(
                  'Generated: ${DateTime.now().toString().split('.')[0]} | Vehicle Tracker System',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
                ),
              ),
            ],
          );
        },
      ),
    );

    // Open print preview
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Fleet_Report_${_formatDate(_selectedDate).replaceAll('/', '-')}',
    );
  }

  pw.Widget _buildPdfCard(String label, String value, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: color, width: 2),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          pw.Container(
            width: 40,
            height: 40,
            decoration: pw.BoxDecoration(
              color: color,
              borderRadius: pw.BorderRadius.circular(20),
            ),
            child: pw.Center(
              child: pw.Text(
                label == 'Jarak Tempuh' ? 'KM' : 'JAM',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fleet Summary'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            onPressed: _printReport,
            icon: const Icon(Icons.print),
            tooltip: 'Print Laporan',
          ),
          TextButton.icon(
            onPressed: _selectDate,
            icon: const Icon(Icons.calendar_today),
            label: Text(_formatDate(_selectedDate)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Service Reminder Banner
                  if (_serviceNeeded)
                    Card(
                      color: Colors.orange.shade100,
                      child: ListTile(
                        leading: const Icon(
                          Icons.build,
                          color: Colors.orange,
                          size: 32,
                        ),
                        title: const Text(
                          '🔧 Waktunya Ganti Oli!',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Sudah ${_kmSinceService.toStringAsFixed(0)} km sejak servis terakhir',
                        ),
                        trailing: ElevatedButton(
                          onPressed: _recordService,
                          child: const Text('Sudah Servis'),
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Daily Stats Header
                  Text(
                    'Statistik ${_formatDate(_selectedDate)}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),

                  const SizedBox(height: 16),

                  // Stats Cards Row
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'Jarak Tempuh',
                          '${_stats?.totalDistanceKm.toStringAsFixed(1) ?? '0'} km',
                          Icons.straighten,
                          Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          'Mesin Menyala',
                          _formatDuration(_stats?.engineHours ?? Duration.zero),
                          Icons.access_time,
                          Colors.green,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Driver Score Card
                  _buildDriverScoreCard(),

                  const SizedBox(height: 24),

                  // Odometer Section
                  Text(
                    'Odometer',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.speed, size: 48, color: Colors.grey),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Total Odometer'),
                                Text(
                                  '${_totalOdometer.toStringAsFixed(1)} km',
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'Sejak Servis',
                                style: TextStyle(fontSize: 12),
                              ),
                              Text(
                                '${_kmSinceService.toStringAsFixed(0)} km',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: _serviceNeeded
                                      ? Colors.orange
                                      : Colors.grey,
                                ),
                              ),
                              Text(
                                'Next: ${(5000 - _kmSinceService).clamp(0, 5000).toStringAsFixed(0)} km',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Event Breakdown
                  Text(
                    'Pelanggaran Hari Ini',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  _buildEventBreakdown(),
                ],
              ),
            ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverScoreCard() {
    final score = _stats?.driverScore ?? 100;
    final color = _getScoreColor(score);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Score Circle
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 4),
              ),
              child: Center(
                child: Text(
                  '$score',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Skor Pengemudi',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    score >= 80
                        ? '🌟 Sangat Baik!'
                        : score >= 60
                        ? '⚠️ Perlu Perbaikan'
                        : '❌ Perlu Evaluasi',
                    style: TextStyle(color: color),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Setiap pelanggaran mengurangi 5 poin',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventBreakdown() {
    final events = _stats?.eventCounts ?? {};

    if (events.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.check_circle, size: 48, color: Colors.green),
                SizedBox(height: 8),
                Text('Tidak ada pelanggaran hari ini'),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      child: Column(
        children: events.entries.map((entry) {
          return ListTile(
            leading: Icon(_getEventIcon(entry.key), color: Colors.red),
            title: Text(_getEventLabel(entry.key)),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${entry.value}x',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  IconData _getEventIcon(String eventType) {
    switch (eventType) {
      case 'overspeed':
        return Icons.speed;
      case 'geofenceIn':
        return Icons.login;
      case 'geofenceOut':
        return Icons.logout;
      case 'idle':
        return Icons.timer;
      case 'harshBraking':
        return Icons.front_loader;
      case 'harshAcceleration':
        return Icons.rocket_launch;
      case 'harshCornering':
        return Icons.turn_sharp_right;
      case 'crash':
        return Icons.car_crash;
      default:
        return Icons.warning;
    }
  }

  String _getEventLabel(String eventType) {
    switch (eventType) {
      case 'overspeed':
        return 'Kecepatan Berlebih';
      case 'geofenceIn':
        return 'Masuk Geofence';
      case 'geofenceOut':
        return 'Keluar Geofence';
      case 'idle':
        return 'Diam Terlalu Lama';
      case 'harshBraking':
        return 'Pengereman Mendadak';
      case 'harshAcceleration':
        return 'Akselerasi Mendadak';
      case 'harshCornering':
        return 'Belok Tajam';
      case 'crash':
        return 'Deteksi Kecelakaan';
      default:
        return eventType;
    }
  }
}
