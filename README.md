# Vehicle Tracker

Aplikasi pelacakan kendaraan real-time dengan Firebase backend, dibangun menggunakan Flutter.

## Fitur Utama

### Real-time Tracking
- Pelacakan lokasi GPS real-time
- Visualisasi rute dengan polyline berwarna berdasarkan kecepatan
- Geofencing dengan notifikasi keluar area

### Autentikasi
- Login & Register dengan Firebase Auth
- Data terpisah per user (multi-user support)
- Logout dengan konfirmasi

### Fleet Summary
- Statistik harian (jarak tempuh, jam mesin, skor pengemudi)
- Tracking odometer
- Pengingat servis berkala (setiap 5000 km)
- Breakdown pelanggaran

### Laporan PDF
- Cetak laporan dengan visualisasi lengkap
- Data kendaraan (pemilik, no. polisi, merk, dll)
- Statistik dan skor pengemudi
- Preview sebelum print

### Deteksi Event
- Overspeed (kelebihan kecepatan)
- Harsh braking/acceleration/cornering
- Geofence exit
- Idle detection
- Crash detection

### Profil Kendaraan
- CRUD data kendaraan
- Nama pemilik, nomor polisi
- Merk, model, tahun, warna
- Nomor rangka & mesin

### History Playback
- Putar ulang riwayat perjalanan
- Filter berdasarkan tanggal
- Visualisasi rute dengan heatmap kecepatan

## Teknologi

- **Framework**: Flutter
- **Backend**: Firebase
  - Authentication
  - Cloud Firestore
- **Maps**: Google Maps Flutter
- **PDF**: pdf, printing packages
- **Sensors**: geolocator, sensors_plus, battery_plus

## Struktur Project

```
lib/
├── main.dart                 # Entry point & home screen
├── login_screen.dart         # Halaman login
├── register_screen.dart      # Halaman register
├── profile_screen.dart       # Profil kendaraan (CRUD)
├── fleet_summary_screen.dart # Statistik & laporan
├── history_playback_screen.dart # Putar ulang riwayat
├── firebase_helper.dart      # Firebase operations
├── event_processor.dart      # Deteksi event
└── models.dart               # Data models
```

## Setup

### 1. Clone & Install Dependencies
```bash
git clone <repo-url>
cd tracking
flutter pub get
```

### 2. Setup Firebase
1. Buat project di [Firebase Console](https://console.firebase.google.com)
2. Aktifkan **Authentication** (Email/Password)
3. Aktifkan **Cloud Firestore** (test mode)
4. Download `google-services.json` → taruh di `android/app/`
5. Download `GoogleService-Info.plist` → taruh di `ios/Runner/`

### 3. Setup Google Maps
1. Dapatkan API Key dari [Google Cloud Console](https://console.cloud.google.com)
2. Aktifkan Maps SDK for Android & iOS
3. Tambahkan key di:
   - `android/app/src/main/AndroidManifest.xml`
   - `ios/Runner/AppDelegate.swift`
   - `web/index.html`

### 4. Run
```bash
flutter run
```

## 🗄️ Struktur Database (Firestore)

```
users/
└── {userId}/
    ├── vehicle_history/  # Data lokasi
    ├── events/           # Log pelanggaran
    ├── fleet_stats/      # Odometer & servis
    └── profiles/         # Data kendaraan
```


