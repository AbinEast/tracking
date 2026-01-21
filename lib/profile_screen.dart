import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_helper.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firebaseHelper = FirebaseHelper();

  final _namaController = TextEditingController();
  final _pemilikController = TextEditingController();
  final _noPolisiController = TextEditingController();
  final _merkController = TextEditingController();
  final _modelController = TextEditingController();
  final _tahunController = TextEditingController();
  final _warnaController = TextEditingController();
  final _noRangkaController = TextEditingController();
  final _noMesinController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _namaController.dispose();
    _pemilikController.dispose();
    _noPolisiController.dispose();
    _merkController.dispose();
    _modelController.dispose();
    _tahunController.dispose();
    _warnaController.dispose();
    _noRangkaController.dispose();
    _noMesinController.dispose();
    super.dispose();
  }

  String get _userId => FirebaseAuth.instance.currentUser?.uid ?? 'default';

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);

    try {
      final profile = await _firebaseHelper.getProfile(_userId);
      if (profile != null) {
        _pemilikController.text = profile['pemilik'] ?? '';
        _namaController.text = profile['nama'] ?? '';
        _noPolisiController.text = profile['noPolisi'] ?? '';
        _merkController.text = profile['merk'] ?? '';
        _modelController.text = profile['model'] ?? '';
        _tahunController.text = profile['tahun'] ?? '';
        _warnaController.text = profile['warna'] ?? '';
        _noRangkaController.text = profile['noRangka'] ?? '';
        _noMesinController.text = profile['noMesin'] ?? '';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      await _firebaseHelper.saveProfile(_userId, {
        'pemilik': _pemilikController.text.trim(),
        'nama': _namaController.text.trim(),
        'noPolisi': _noPolisiController.text.trim().toUpperCase(),
        'merk': _merkController.text.trim(),
        'model': _modelController.text.trim(),
        'tahun': _tahunController.text.trim(),
        'warna': _warnaController.text.trim(),
        'noRangka': _noRangkaController.text.trim().toUpperCase(),
        'noMesin': _noMesinController.text.trim().toUpperCase(),
        'updatedAt': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        setState(() => _isEditing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profil berhasil disimpan'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteProfile() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Profil'),
        content: const Text(
          'Apakah Anda yakin ingin menghapus semua data profil?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);

    try {
      await _firebaseHelper.deleteProfile(_userId);

      // Clear all fields
      _pemilikController.clear();
      _namaController.clear();
      _noPolisiController.clear();
      _merkController.clear();
      _modelController.clear();
      _tahunController.clear();
      _warnaController.clear();
      _noRangkaController.clear();
      _noMesinController.clear();

      if (mounted) {
        setState(() => _isEditing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profil berhasil dihapus'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil Kendaraan'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (!_isLoading && !_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit Profil',
              onPressed: () => setState(() => _isEditing = true),
            ),
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: 'Hapus Profil',
              onPressed: _deleteProfile,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Card
                    Card(
                      color: Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.directions_car,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _pemilikController.text.isEmpty
                                        ? 'Pemilik Belum Diisi'
                                        : _pemilikController.text,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  Text(
                                    _namaController.text.isEmpty
                                        ? 'Kendaraan Saya'
                                        : _namaController.text,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    _noPolisiController.text.isEmpty
                                        ? 'Belum ada nomor polisi'
                                        : _noPolisiController.text,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Form Fields
                    const Text(
                      'INFORMASI DASAR',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 12),

                    _buildTextField(
                      controller: _pemilikController,
                      label: 'Nama Pemilik',
                      icon: Icons.person,
                      enabled: _isEditing,
                    ),
                    _buildTextField(
                      controller: _namaController,
                      label: 'Nama Kendaraan',
                      icon: Icons.label,
                      enabled: _isEditing,
                    ),
                    _buildTextField(
                      controller: _noPolisiController,
                      label: 'Nomor Polisi',
                      icon: Icons.confirmation_number,
                      enabled: _isEditing,
                      textCapitalization: TextCapitalization.characters,
                    ),

                    const SizedBox(height: 24),
                    const Text(
                      'DETAIL KENDARAAN',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _merkController,
                            label: 'Merk',
                            icon: Icons.business,
                            enabled: _isEditing,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            controller: _modelController,
                            label: 'Model',
                            icon: Icons.category,
                            enabled: _isEditing,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _tahunController,
                            label: 'Tahun',
                            icon: Icons.calendar_today,
                            enabled: _isEditing,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            controller: _warnaController,
                            label: 'Warna',
                            icon: Icons.palette,
                            enabled: _isEditing,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                    const Text(
                      'IDENTITAS KENDARAAN',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 12),

                    _buildTextField(
                      controller: _noRangkaController,
                      label: 'Nomor Rangka',
                      icon: Icons.qr_code,
                      enabled: _isEditing,
                      textCapitalization: TextCapitalization.characters,
                    ),
                    _buildTextField(
                      controller: _noMesinController,
                      label: 'Nomor Mesin',
                      icon: Icons.engineering,
                      enabled: _isEditing,
                      textCapitalization: TextCapitalization.characters,
                    ),

                    const SizedBox(height: 32),

                    // Save Button
                    if (_isEditing)
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveProfile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: Text(
                            _isSaving ? 'Menyimpan...' : 'Simpan Profil',
                          ),
                        ),
                      ),

                    if (_isEditing) const SizedBox(height: 12),

                    if (_isEditing)
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() => _isEditing = false);
                            _loadProfile(); // Reload original data
                          },
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Batal'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool enabled = true,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.words,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: !enabled,
          fillColor: enabled ? null : Colors.grey.shade100,
        ),
      ),
    );
  }
}
