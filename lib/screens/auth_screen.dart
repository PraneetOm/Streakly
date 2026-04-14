import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/habit.dart';
import '../models/session.dart';

class AuthScreen extends StatefulWidget {
  final void Function(BuildContext context) onLoginSuccess;

  const AuthScreen({super.key, required this.onLoginSuccess});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // 🔥 Connectivity Tracking
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  bool _hasInternet = true;
  bool _isCheckingConnectivity = true;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;

  bool _isLogin = true;
  bool _isLoading = false;
  String _syncStatus = "";

  String _backgroundImageUrl =
      'https://i.ibb.co/C5G3cTCP/image-2026-04-14-190706911.png';

  @override
  void initState() {
    super.initState();
    _initConnectivity();
    _loadCustomBackground();
  }

  // 🔥 Initialize and Listen to Network State
  Future<void> _initConnectivity() async {
    final connectivity = Connectivity();
    
    // Initial check
    final initialResult = await connectivity.checkConnectivity();
    _updateConnectionState(initialResult);

    // Listen for live changes
    _connectivitySubscription = connectivity.onConnectivityChanged.listen(_updateConnectionState);
  }

  void _updateConnectionState(List<ConnectivityResult> results) {
    if (!mounted) return;
    
    // If the list is empty or ONLY contains 'none', we are offline.
    bool isOffline = results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    
    setState(() {
      _hasInternet = !isOffline;
      _isCheckingConnectivity = false;
    });
  }

  Future<void> _loadCustomBackground() async {
    final settingsBox = await Hive.openBox('settings');
    final savedImage = settingsBox.get('startup_image');

    if (savedImage != null && mounted) {
      setState(() => _backgroundImageUrl = savedImage);
    }
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    if (!_hasInternet) return; // Block if offline
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _syncStatus = _isLogin ? "Authenticating..." : "Creating account...";
    });

    try {
      final supabase = Supabase.instance.client;
      AuthResponse response;

      if (_isLogin) {
        response = await supabase.auth.signInWithPassword(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
      } else {
        response = await supabase.auth.signUp(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );

        if (response.user != null) {
          setState(() => _syncStatus = "Setting up profile...");
          await supabase.from('profiles').insert({
            'id': response.user!.id,
            'full_name': _nameCtrl.text.trim(),
          });
        }
      }

      if (response.user != null) {
        await _syncCloudToLocal(response.user!.id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Welcome! Data synced successfully.', style: TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
          widget.onLoginSuccess(context);
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade600, behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red.shade600, behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _syncCloudToLocal(String userId) async {
    setState(() => _syncStatus = "Syncing your habits...");
    final supabase = Supabase.instance.client;

    try {
      final habitBox = Hive.box<Habit>('habits');
      final sessionBox = Hive.box<Sessions>('sessions');
      await habitBox.clear();
      await sessionBox.clear();

      final results = await Future.wait([
        supabase.from('habits').select().eq('user_id', userId),
        supabase.from('streaks').select().eq('user_id', userId),
        supabase.from('habit_sessions').select().eq('user_id', userId),
      ]);

      final List<dynamic> habitsData = results[0];
      final List<dynamic> streaksData = results[1];
      final List<dynamic> sessionsData = results[2];

      setState(() => _syncStatus = "Restoring your progress...");

      for (var hData in habitsData) {
        final matchingStreaks = streaksData
            .where((s) => s['habit_id'] == hData['id'])
            .toList();
        final streakRow = matchingStreaks.isNotEmpty
            ? matchingStreaks.first
            : null;

        int currentStreak = streakRow != null
            ? (streakRow['current_streak'] ?? 0)
            : 0;
        DateTime? lastCompleted = streakRow?['last_completed_date'] != null
            ? DateTime.parse(streakRow['last_completed_date'])
            : null;

        HabitType hType = HabitType.values.firstWhere(
          (e) => e.name == hData['type'],
          orElse: () => HabitType.duration,
        );

        int totalHabitXp = sessionsData
            .where((s) => s['habit_id'] == hData['id'])
            .fold(
              0,
              (sum, s) => sum + ((s['flow_points'] as num?)?.toInt() ?? 0),
            );

        final newHabit = Habit(
          id: hData['id'],
          title: hData['title'] ?? 'Unnamed Habit',
          type: hType,
          unit: hData['unit'] ?? 'units',
          dailyTarget: (hData['daily_target'] as num?)?.toDouble() ?? 1.0,
          xpPerUnit: (hData['xp_per_target'] as num?)?.toDouble() ?? 10.0,
          streak: currentStreak,
          totalXP: totalHabitXp,
          lastCompletedDate: lastCompleted,
          frequency: HabitFrequency.daily,
          isArchived: hData['isArchived'] ?? hData['is_archived'] ?? false,
        );

        await habitBox.put(newHabit.id, newHabit);
      }

      setState(() => _syncStatus = "Finalizing...");
      for (var sData in sessionsData) {
        final newSession = Sessions(
          habitId: sData['habit_id'],
          value: (sData['value'] as num?)?.toDouble() ?? 1.0,
          date: DateTime.parse(sData['started_at'] ?? sData['created_at']).toLocal(),
          xpEarned: (sData['flow_points'] as num?)?.toInt() ?? 0,
        );
        await sessionBox.add(newSession);
      }
    } catch (e) {
      debugPrint("❌ Sync Error: $e");
      throw Exception("Failed to sync data from cloud.");
    }
  }

  ImageProvider _getImageProvider(String path) {
    if (path.startsWith('http')) {
      return NetworkImage(path);
    } else {
      return FileImage(File(path));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigo.shade900,
      body: Stack(
        children: [          
          // 🔥 THE FIX: Bulletproof Image Background with errorBuilder
          Positioned.fill(
            child: Image(
              image: _getImageProvider(_backgroundImageUrl),
              fit: BoxFit.cover, // Better than fill so it doesn't stretch weirdly
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.indigo.shade900, Colors.blue.shade900],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.4),
                    Colors.black.withValues(alpha: 0.8),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          SafeArea(
            child: _isCheckingConnectivity
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeInCubic,
                    child: !_hasInternet 
                        ? _buildOfflineState() 
                        : _buildAuthForm(),
                  ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 🔥 Beautiful "Offline" State UX
  // ==========================================
  Widget _buildOfflineState() {
    return Center(
      key: const ValueKey('offline_state'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(32.0),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.red.shade400.withValues(alpha: 0.2), 
                shape: BoxShape.circle
              ),
              child: Icon(Icons.wifi_off_rounded, size: 56, color: Colors.red.shade300),
            ),
            const SizedBox(height: 24),
            const Text(
              "No Connection",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5),
            ),
            const SizedBox(height: 12),
            Text(
              "We need a network connection to log you in and sync your habits. Please turn on Wi-Fi or Cellular Data.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.8), height: 1.4),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 56,
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  setState(() => _isCheckingConnectivity = true);
                  final results = await Connectivity().checkConnectivity();
                  _updateConnectionState(results);
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text("Try Again", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 🔥 The Auth Form
  // ==========================================
  Widget _buildAuthForm() {
    return Center(
      key: const ValueKey('auth_state'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              _isLogin ? "Welcome Back" : "Start Your Journey",
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isLogin
                  ? "Log in to sync your habits and pick up where you left off."
                  : "Commit to your goals and build unbreakable streaks.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 48),

            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOutCubic,
                      child: _isLogin
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: TextFormField(
                                controller: _nameCtrl,
                                textCapitalization: TextCapitalization.words,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: "Full Name",
                                  labelStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                  prefixIcon: Icon(
                                    Icons.person_outline_rounded,
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                  filled: true,
                                  fillColor: Colors.black.withValues(alpha: 0.2),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                validator: (value) =>
                                    !_isLogin && (value == null || value.trim().isEmpty)
                                        ? 'Please enter your name'
                                        : null,
                              ),
                            ),
                    ),

                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "Email",
                        labelStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                        prefixIcon: Icon(
                          Icons.email_outlined,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                        filled: true,
                        fillColor: Colors.black.withValues(alpha: 0.2),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator: (value) =>
                          value != null && value.contains('@')
                              ? null
                              : 'Enter a valid email',
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscurePassword, 
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "Password",
                        labelStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                        prefixIcon: Icon(
                          Icons.lock_outline_rounded,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                        filled: true,
                        fillColor: Colors.black.withValues(alpha: 0.2),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator: (value) =>
                          value != null && value.length >= 6
                              ? null
                              : 'Password must be 6+ characters',
                    ),
                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _authenticate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isLoading
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _syncStatus,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              )
                            : Text(
                                _isLogin ? "Log In" : "Sign Up",
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            TextButton(
              onPressed: _isLoading
                  ? null
                  : () => setState(() {
                        _isLogin = !_isLogin;
                        _formKey.currentState?.reset();
                      }),
              child: Text(
                _isLogin
                    ? "Don't have an account? Sign Up"
                    : "Already have an account? Log In",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// import 'dart:io';
// import 'package:flutter/material.dart';
// import 'package:hive_flutter/hive_flutter.dart';
// import 'package:supabase_flutter/supabase_flutter.dart';
// import '../models/habit.dart';
// import '../models/session.dart';

// class AuthScreen extends StatefulWidget {
//   final void Function(BuildContext context) onLoginSuccess;

//   const AuthScreen({super.key, required this.onLoginSuccess});

//   @override
//   State<AuthScreen> createState() => _AuthScreenState();
// }

// class _AuthScreenState extends State<AuthScreen> {
//   final _nameCtrl = TextEditingController();
//   final _emailCtrl = TextEditingController();
//   final _passwordCtrl = TextEditingController();
//   final _formKey = GlobalKey<FormState>();
//   bool _obscurePassword = true;

//   bool _isLogin = true;
//   bool _isLoading = false;
//   String _syncStatus = "";

//   // 🔥 FIX 1: Removed 'final' so we can update it from Hive
//   String _backgroundImageUrl =
//       'https://i.ibb.co/C5G3cTCP/image-2026-04-14-190706911.png';

//   // 🔥 FIX 2: Added initState to trigger the fetch
//   @override
//   void initState() {
//     super.initState();
//     _loadCustomBackground();
//   }

//   // 🔥 FIX 3: Actually fetch the custom image from Hive!
//   Future<void> _loadCustomBackground() async {
//     final settingsBox = await Hive.openBox('settings');
//     final savedImage = settingsBox.get('startup_image');

//     if (savedImage != null && mounted) {
//       setState(() => _backgroundImageUrl = savedImage);
//     }
//   }

//   @override
//   void dispose() {
//     _nameCtrl.dispose();
//     _emailCtrl.dispose();
//     _passwordCtrl.dispose();
//     super.dispose();
//   }

//   Future<void> _authenticate() async {
//     if (!_formKey.currentState!.validate()) return;
//     FocusScope.of(context).unfocus();

//     setState(() {
//       _isLoading = true;
//       _syncStatus = _isLogin ? "Authenticating..." : "Creating account...";
//     });

//     try {
//       final supabase = Supabase.instance.client;
//       AuthResponse response;

//       if (_isLogin) {
//         response = await supabase.auth.signInWithPassword(
//           email: _emailCtrl.text.trim(),
//           password: _passwordCtrl.text,
//         );
//       } else {
//         response = await supabase.auth.signUp(
//           email: _emailCtrl.text.trim(),
//           password: _passwordCtrl.text,
//         );

//         if (response.user != null) {
//           setState(() => _syncStatus = "Setting up profile...");
//           await supabase.from('profiles').insert({
//             'id': response.user!.id,
//             'full_name': _nameCtrl.text.trim(),
//           });
//         }
//       }

//       if (response.user != null) {
//         await _syncCloudToLocal(response.user!.id);

//         if (mounted) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             const SnackBar(
//               content: Text('Welcome! Data synced successfully.'),
//               backgroundColor: Colors.green,
//             ),
//           );
//           widget.onLoginSuccess(context);
//         }
//       }
//     } on AuthException catch (e) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text(e.message), backgroundColor: Colors.red),
//         );
//       }
//     } catch (e) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
//         );
//       }
//     } finally {
//       if (mounted) setState(() => _isLoading = false);
//     }
//   }

//   Future<void> _syncCloudToLocal(String userId) async {
//     setState(() => _syncStatus = "Syncing your habits...");
//     final supabase = Supabase.instance.client;

//     try {
//       final habitBox = Hive.box<Habit>('habits');
//       final sessionBox = Hive.box<Sessions>('sessions');
//       await habitBox.clear();
//       await sessionBox.clear();

//       final results = await Future.wait([
//         supabase.from('habits').select().eq('user_id', userId),
//         supabase.from('streaks').select().eq('user_id', userId),
//         supabase.from('habit_sessions').select().eq('user_id', userId),
//       ]);

//       final List<dynamic> habitsData = results[0];
//       final List<dynamic> streaksData = results[1];
//       final List<dynamic> sessionsData = results[2];

//       setState(() => _syncStatus = "Restoring your progress...");

//       for (var hData in habitsData) {
//         final matchingStreaks = streaksData
//             .where((s) => s['habit_id'] == hData['id'])
//             .toList();
//         final streakRow = matchingStreaks.isNotEmpty
//             ? matchingStreaks.first
//             : null;

//         int currentStreak = streakRow != null
//             ? (streakRow['current_streak'] ?? 0)
//             : 0;
//         DateTime? lastCompleted = streakRow?['last_completed_date'] != null
//             ? DateTime.parse(streakRow['last_completed_date'])
//             : null;

//         HabitType hType = HabitType.values.firstWhere(
//           (e) => e.name == hData['type'],
//           orElse: () => HabitType.duration,
//         );

//         int totalHabitXp = sessionsData
//             .where((s) => s['habit_id'] == hData['id'])
//             .fold(
//               0,
//               (sum, s) => sum + ((s['flow_points'] as num?)?.toInt() ?? 0),
//             );

//         final newHabit = Habit(
//           id: hData['id'],
//           title: hData['title'] ?? 'Unnamed Habit',
//           type: hType,
//           unit: hData['unit'] ?? 'units',
//           dailyTarget: (hData['daily_target'] as num?)?.toDouble() ?? 1.0,
//           xpPerUnit: (hData['xp_per_target'] as num?)?.toDouble() ?? 10.0,
//           streak: currentStreak,
//           totalXP: totalHabitXp,
//           lastCompletedDate: lastCompleted,
//           frequency: HabitFrequency.daily,
//           isArchived: hData['isArchived'] ?? hData['is_archived'] ?? false,
//         );

//         await habitBox.put(newHabit.id, newHabit);
//       }

//       setState(() => _syncStatus = "Finalizing...");
//       for (var sData in sessionsData) {
//         final newSession = Sessions(
//           habitId: sData['habit_id'],
//           value: (sData['value'] as num?)?.toDouble() ?? 1.0,
//           date: DateTime.parse(sData['started_at'] ?? sData['created_at']),
//           xpEarned: (sData['flow_points'] as num?)?.toInt() ?? 0,
//         );
//         await sessionBox.add(newSession);
//       }
//     } catch (e) {
//       debugPrint("❌ Sync Error: $e");
//       throw Exception("Failed to sync data from cloud.");
//     }
//   }

//   ImageProvider _getImageProvider(String path) {
//     if (path.startsWith('http')) {
//       return NetworkImage(path);
//     } else {
//       return FileImage(File(path));
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: Stack(
//         children: [          
//           Positioned.fill(
//             child: Image(
//               image: _getImageProvider(_backgroundImageUrl),
//               fit: BoxFit.fill,
//             ),
//           ),
//           Positioned.fill(
//             child: Container(
//               decoration: BoxDecoration(
//                 gradient: LinearGradient(
//                   colors: [
//                     Colors.black.withValues(alpha: 0.3),
//                     Colors.black.withValues(alpha: 0.8),
//                   ],
//                   begin: Alignment.topCenter,
//                   end: Alignment.bottomCenter,
//                 ),
//               ),
//             ),
//           ),
//           SafeArea(
//             child: Center(
//               child: SingleChildScrollView(
//                 padding: const EdgeInsets.symmetric(horizontal: 24),
//                 child: Column(
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   crossAxisAlignment: CrossAxisAlignment.stretch,
//                   children: [
//                     const Icon(
//                       Icons.auto_awesome_rounded,
//                       color: Colors.white,
//                       size: 64,
//                     ),
//                     const SizedBox(height: 16),
//                     Text(
//                       _isLogin ? "Welcome Back" : "Start Your Journey",
//                       textAlign: TextAlign.center,
//                       style: const TextStyle(
//                         fontSize: 32,
//                         fontWeight: FontWeight.w900,
//                         color: Colors.white,
//                         letterSpacing: -0.5,
//                       ),
//                     ),
//                     const SizedBox(height: 8),
//                     Text(
//                       _isLogin
//                           ? "Log in to sync your habits and pick up where you left off."
//                           : "Commit to your goals and build unbreakable streaks.",
//                       textAlign: TextAlign.center,
//                       style: TextStyle(
//                         fontSize: 15,
//                         color: Colors.white.withValues(alpha: 0.8),
//                       ),
//                     ),
//                     const SizedBox(height: 48),

//                     Container(
//                       padding: const EdgeInsets.all(24),
//                       decoration: BoxDecoration(
//                         color: Colors.white.withValues(alpha: 0.1),
//                         borderRadius: BorderRadius.circular(28),
//                         border: Border.all(
//                           color: Colors.white.withValues(alpha: 0.2),
//                         ),
//                       ),
//                       child: Form(
//                         key: _formKey,
//                         child: Column(
//                           children: [
//                             AnimatedSize(
//                               duration: const Duration(milliseconds: 300),
//                               curve: Curves.easeInOutCubic,
//                               child: _isLogin
//                                   ? const SizedBox.shrink()
//                                   : Padding(
//                                       padding: const EdgeInsets.only(
//                                         bottom: 16,
//                                       ),
//                                       child: TextFormField(
//                                         controller: _nameCtrl,
//                                         textCapitalization:
//                                             TextCapitalization.words,
//                                         style: const TextStyle(
//                                           color: Colors.white,
//                                         ),
//                                         decoration: InputDecoration(
//                                           labelText: "Full Name",
//                                           labelStyle: TextStyle(
//                                             color: Colors.white.withValues(
//                                               alpha: 0.7,
//                                             ),
//                                           ),
//                                           prefixIcon: Icon(
//                                             Icons.person_outline_rounded,
//                                             color: Colors.white.withValues(
//                                               alpha: 0.7,
//                                             ),
//                                           ),
//                                           filled: true,
//                                           fillColor: Colors.black.withValues(
//                                             alpha: 0.2,
//                                           ),
//                                           border: OutlineInputBorder(
//                                             borderRadius: BorderRadius.circular(
//                                               16,
//                                             ),
//                                             borderSide: BorderSide.none,
//                                           ),
//                                         ),
//                                         validator: (value) =>
//                                             !_isLogin &&
//                                                 (value == null ||
//                                                     value.trim().isEmpty)
//                                             ? 'Please enter your name'
//                                             : null,
//                                       ),
//                                     ),
//                             ),

//                             TextFormField(
//                               controller: _emailCtrl,
//                               keyboardType: TextInputType.emailAddress,
//                               style: const TextStyle(color: Colors.white),
//                               decoration: InputDecoration(
//                                 labelText: "Email",
//                                 labelStyle: TextStyle(
//                                   color: Colors.white.withValues(alpha: 0.7),
//                                 ),
//                                 prefixIcon: Icon(
//                                   Icons.email_outlined,
//                                   color: Colors.white.withValues(alpha: 0.7),
//                                 ),
//                                 filled: true,
//                                 fillColor: Colors.black.withValues(alpha: 0.2),
//                                 border: OutlineInputBorder(
//                                   borderRadius: BorderRadius.circular(16),
//                                   borderSide: BorderSide.none,
//                                 ),
//                               ),
//                               validator: (value) =>
//                                   value != null && value.contains('@')
//                                   ? null
//                                   : 'Enter a valid email',
//                             ),
//                             const SizedBox(height: 16),

//                             TextFormField(
//                               controller: _passwordCtrl,
//                               obscureText:
//                                   _obscurePassword, // 🔥 Now uses the state variable
//                               style: const TextStyle(color: Colors.white),
//                               decoration: InputDecoration(
//                                 labelText: "Password",
//                                 labelStyle: TextStyle(
//                                   color: Colors.white.withValues(alpha: 0.7),
//                                 ),
//                                 prefixIcon: Icon(
//                                   Icons.lock_outline_rounded,
//                                   color: Colors.white.withValues(alpha: 0.7),
//                                 ),
//                                 // 🔥 NEW: The view/hide eye toggle button
//                                 suffixIcon: IconButton(
//                                   icon: Icon(
//                                     _obscurePassword
//                                         ? Icons.visibility_off_rounded
//                                         : Icons.visibility_rounded,
//                                     color: Colors.white.withValues(alpha: 0.7),
//                                   ),
//                                   onPressed: () {
//                                     setState(() {
//                                       _obscurePassword = !_obscurePassword;
//                                     });
//                                   },
//                                 ),
//                                 filled: true,
//                                 fillColor: Colors.black.withValues(alpha: 0.2),
//                                 border: OutlineInputBorder(
//                                   borderRadius: BorderRadius.circular(16),
//                                   borderSide: BorderSide.none,
//                                 ),
//                               ),
//                               validator: (value) =>
//                                   value != null && value.length >= 6
//                                   ? null
//                                   : 'Password must be 6+ characters',
//                             ),
//                             const SizedBox(height: 32),

//                             SizedBox(
//                               width: double.infinity,
//                               height: 56,
//                               child: ElevatedButton(
//                                 onPressed: _isLoading ? null : _authenticate,
//                                 style: ElevatedButton.styleFrom(
//                                   backgroundColor: Colors.white,
//                                   foregroundColor: Colors.black87,
//                                   shape: RoundedRectangleBorder(
//                                     borderRadius: BorderRadius.circular(16),
//                                   ),
//                                 ),
//                                 child: _isLoading
//                                     ? Row(
//                                         mainAxisAlignment:
//                                             MainAxisAlignment.center,
//                                         children: [
//                                           const SizedBox(
//                                             width: 20,
//                                             height: 20,
//                                             child: CircularProgressIndicator(
//                                               strokeWidth: 2,
//                                               color: Colors.black87,
//                                             ),
//                                           ),
//                                           const SizedBox(width: 12),
//                                           Text(
//                                             _syncStatus,
//                                             style: const TextStyle(
//                                               fontWeight: FontWeight.bold,
//                                             ),
//                                           ),
//                                         ],
//                                       )
//                                     : Text(
//                                         _isLogin ? "Log In" : "Sign Up",
//                                         style: const TextStyle(
//                                           fontSize: 16,
//                                           fontWeight: FontWeight.bold,
//                                         ),
//                                       ),
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),
//                     ),
//                     const SizedBox(height: 24),

//                     TextButton(
//                       onPressed: _isLoading
//                           ? null
//                           : () => setState(() {
//                               _isLogin = !_isLogin;
//                               _formKey.currentState?.reset();
//                             }),
//                       child: Text(
//                         _isLogin
//                             ? "Don't have an account? Sign Up"
//                             : "Already have an account? Log In",
//                         style: const TextStyle(
//                           color: Colors.white,
//                           fontWeight: FontWeight.w600,
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
