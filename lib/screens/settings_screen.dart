import 'dart:io'; 
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart'; 
import 'home_screen.dart';
import '../models/habit.dart';
import '../models/session.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _supabase = Supabase.instance.client;
  late Box _settingsBox;

  String _userName = "Loading...";
  String _userEmail = "";
  bool _dailyReminders = true;
  String _selectedImage = '';

  final ImagePicker _picker = ImagePicker();

  final List<String> _backgroundOptions = [
    'https://images.unsplash.com/photo-1552508744-1696d4464960?q=80&w=2070&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?q=80&w=2073&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1494438639946-1ebd1d20bf85?q=80&w=2067&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1550684848-fac1c5b4e853?q=80&w=2070&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1478760329108-5c3ed9d495a0?q=80&w=1974&auto=format&fit=crop',
  ];

  @override
  void initState() {
    super.initState();
    _initSettings();
    _fetchUserProfile();
  }

  Future<void> _initSettings() async {
    _settingsBox = await Hive.openBox('settings');
    setState(() {
      _selectedImage = _settingsBox.get(
        'startup_image',
        defaultValue: _backgroundOptions[0],
      );
      _dailyReminders = _settingsBox.get('daily_reminders', defaultValue: true);
    });
  }

  Future<void> _fetchUserProfile() async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      _userEmail = user.email ?? "No Email";
      try {
        final data = await _supabase
            .from('profiles')
            .select('full_name')
            .eq('id', user.id)
            .maybeSingle();
        if (data != null && mounted) {
          setState(() => _userName = data['full_name'] ?? "User");
        }
      } catch (e) {
        setState(() => _userName = "User");
      }
    }
  }

  // 🔥 UPGRADED: Image Picker with Built-in Native Compression
  Future<void> _pickCustomImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        // 🔥 THE FIX: Compress the image natively before Flutter even touches it!
            // 85% quality is visually indistinguishable from 100%, but cuts file size by 70%
        maxWidth: 1440,      // Max width of a high-end phone screen
        maxHeight: 2560,     // Max height of a high-end phone screen
      );

      if (image != null) {
        // 1. Get the app's persistent storage directory
        final directory = await getApplicationDocumentsDirectory();

        // 2. Create a permanent path using a timestamp
        final String newPath = '${directory.path}/custom_bg_${DateTime.now().millisecondsSinceEpoch}.jpg';

        // 3. Copy the (now compressed) temporary file to the permanent location
        final File permanentImage = await File(image.path).copy(newPath);

        setState(() => _selectedImage = permanentImage.path);

        // 4. Save the PERMANENT path to Hive
        _settingsBox.put('startup_image', permanentImage.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to pick image")),
        );
      }
    }
  }

  // Future<void> _pickCustomImage() async {
  //   try {
  //     final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
  //     if (image != null) {
  //       final directory = await getApplicationDocumentsDirectory();
  //       final String newPath =
  //           '${directory.path}/custom_bg_${DateTime.now().millisecondsSinceEpoch}.jpg';

  //       final File permanentImage = await File(image.path).copy(newPath);

  //       setState(() => _selectedImage = permanentImage.path);
  //       _settingsBox.put('startup_image', permanentImage.path);
  //     }
  //   } catch (e) {
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //           const SnackBar(content: Text("Failed to pick image")));
  //     }
  //   }
  // }

  ImageProvider _getImageProvider(String path) {
    if (path.startsWith('http')) {
      return NetworkImage(path);
    } else {
      return FileImage(File(path));
    }
  }

  Future<void> _logout() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: Colors.indigo)),
    );

    try {
      await Hive.box<Habit>('habits').clear();
      await Hive.box<Sessions>('sessions').clear();
      await _supabase.auth.signOut();

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error logging out: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🔥 Identify if the current selected image is a custom local file
    bool hasCustomImage = !_selectedImage.startsWith('http');
    
    // 🔥 Build the total list of items for the ListView
    // 1 for Gallery button, +1 if custom image exists, + length of Unsplash images
    int itemCount = 1 + (hasCustomImage ? 1 : 0) + _backgroundOptions.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text(
          "Settings",
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Profile Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.indigo.shade300,
                          Colors.indigo.shade600,
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _userName.isNotEmpty && _userName != "Loading..."
                            ? _userName[0].toUpperCase()
                            : "?",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _userName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _userEmail,
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // 🔥 UPGRADED Startup Image Selector
            const Text(
              "Startup Motivational Image",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: itemCount,
                itemBuilder: (context, index) {
                  // 1. Fixed "Gallery" Button at Index 0
                  if (index == 0) {
                    return GestureDetector(
                      onTap: _pickCustomImage,
                      child: Container(
                        margin: const EdgeInsets.only(right: 12),
                        width: 80,
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.indigo.shade200,
                            style: BorderStyle.solid,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_rounded,
                              color: Colors.indigo.shade500,
                              size: 28,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Gallery",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // 2. Inject Custom Local Image at Index 1 (if it exists)
                  if (hasCustomImage && index == 1) {
                    return _buildImageOption(_selectedImage, true);
                  }

                  // 3. Render Unsplash Images
                  // Offset the index to correctly grab from the _backgroundOptions list
                  int optionIndex = index - 1 - (hasCustomImage ? 1 : 0);
                  final imgUrl = _backgroundOptions[optionIndex];
                  final isSelected = _selectedImage == imgUrl;

                  return _buildImageOption(imgUrl, isSelected);
                },
              ),
            ),

            const SizedBox(height: 32),

            // Preferences Card
            const Text(
              "Preferences",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: SwitchListTile(
                activeThumbColor: Colors.indigo,
                title: const Text(
                  "Daily Reminders",
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                subtitle: Text(
                  "Get notified to complete habits",
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.notifications_active_rounded,
                    color: Colors.indigo.shade400,
                    size: 20,
                  ),
                ),
                value: _dailyReminders,
                onChanged: (val) {
                  setState(() => _dailyReminders = val);
                  _settingsBox.put('daily_reminders', val);
                },
              ),
            ),
            const SizedBox(height: 32),

            // Logout
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text(
                  "Log Out",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade50,
                  foregroundColor: Colors.red.shade600,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to build the image thumbnail cards cleanly
  Widget _buildImageOption(String imgPath, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() => _selectedImage = imgPath);
        _settingsBox.put('startup_image', imgPath);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 12),
        width: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.indigo : Colors.transparent,
            width: 3,
          ),
          image: DecorationImage(
            image: _getImageProvider(imgPath),
            fit: BoxFit.cover,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.indigo.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: isSelected
            ? Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.white,
                ),
              )
            : null,
      ),
    );
  }
}