import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:newapp/screens/hall_of_fame_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/habit.dart';
import 'habit_list_screen.dart';
import 'analytics_screen.dart';
import 'group_list_screen.dart';
import 'auth_screen.dart';
import 'settings_screen.dart'; // 🔥 Imported Settings Screen

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  final PageController _pageController = PageController();
  AnalyticsRangeType _analyticsRange = AnalyticsRangeType.monthly;

  DateTime? _customStart;
  DateTime? _customEnd;

  @override
  void initState() {
    super.initState();

    // 🔥 THE GATEKEEPER: Check auth status the moment the app opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuthentication();
    });
  }

  void _checkAuthentication() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      // If not logged in, force them to the Auth Screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AuthScreen(
            onLoginSuccess: (authContext) {
              Navigator.pushReplacement(
                authContext,
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              );
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Hive.box<Habit>('habits').listenable(),
      builder: (context, Box<Habit> box, _) {
        return Scaffold(
          backgroundColor: const Color(0xFFF4F6F9),
          // 🔥 REMOVED extendBody: true to prevent overlap with the FAB
          appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            "Streakly",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.black87,
              letterSpacing: -1.0,
              fontSize: 24,
            ),
          ),
          centerTitle: false,
          actions: [
            // 💰 Optimized Coin Badge
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.amber.shade300, Colors.orange.shade500],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ValueListenableBuilder(
                valueListenable: Hive.box<Habit>('habits').listenable(),
                builder: (context, Box<Habit> box, _) {
                  int totalXP = box.values.fold(
                    0,
                    (sum, h) => sum + h.totalXP,
                  );
                  int totalCoins = totalXP ~/ 1000;
                  return Row(
                    children: [
                      const Icon(
                        Icons.monetization_on_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "$totalCoins",
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // 👥 Groups Icon
            _buildAppBarAction(
              icon: Icons.groups_rounded,
              color: Colors.indigo.shade600,
              onTap: () async {
                final user = Supabase.instance.client.auth.currentUser;
                if (user == null) {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const _GroupsLockedView(),
                    ),
                  );
                  if (Supabase.instance.client.auth.currentUser == null) return;
                }
                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GroupListScreen()),
                );
              },
            ),

            // 🔥 NEW: 3-Dot Menu for Hall of Fame & Settings
            Container(
              margin: const EdgeInsets.only(right: 16, top: 8, bottom: 8, left: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: Colors.grey.shade700, size: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                color: Colors.white,
                elevation: 6,
                offset: const Offset(0, 45), // Drops it nicely below the action bar
                onSelected: (value) {
                  if (value == 'hall_of_fame') {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const HallOfFameScreen()));
                  } else if (value == 'settings') {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                  }
                },
                itemBuilder: (BuildContext context) => [
                  PopupMenuItem<String>(
                    value: 'hall_of_fame',
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.amber.shade50, shape: BoxShape.circle),
                          child: Icon(Icons.emoji_events_rounded, color: Colors.amber.shade600, size: 16),
                        ),
                        const SizedBox(width: 12),
                        const Text('Hall of Fame', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'settings',
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
                          child: Icon(Icons.settings_rounded, color: Colors.grey.shade700, size: 16),
                        ),
                        const SizedBox(width: 12),
                        const Text('Settings', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
          body: PageView(
            controller: _pageController,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (i) => setState(() => _index = i),
            children: [
              const HabitListScreen(),
              AnalyticsScreen(
                selectedRange: _analyticsRange,
                customStart: _customStart,
                customEnd: _customEnd,
                onRangeChanged: (range, start, end) {
                  setState(() {
                    _analyticsRange = range;
                    _customStart = start;
                    _customEnd = end;
                  });
                },
              ),
            ],
          ),

          // 🔥 Fixed Bottom Navigation Bar (No Overlaps!)
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30),
              ), // Only round the top
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ), // Shadow casts upwards
              ],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30),
              ),
              child: BottomNavigationBar(
                backgroundColor: Colors.white,
                currentIndex: _index,
                elevation: 0,
                onTap: (i) {
                  setState(() => _index = i);
                  _pageController.animateToPage(
                    i,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                  );
                },
                selectedItemColor: Colors.indigo.shade600,
                unselectedItemColor: Colors.grey.shade400,
                selectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.space_dashboard_rounded),
                    label: 'Dashboard',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.insights_rounded),
                    label: 'Analytics',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// Helper for clean AppBar buttons
Widget _buildAppBarAction({
  required IconData icon,
  required Color color,
  required VoidCallback onTap,
}) {
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: IconButton(
      icon: Icon(icon, color: color, size: 20),
      onPressed: onTap,
    ),
  );
}

// ==========================================
// 🔥 Upgraded Locked View
// ==========================================
class _GroupsLockedView extends StatelessWidget {
  const _GroupsLockedView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.indigo.withValues(alpha: 0.05),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
              border: Border.all(color: Colors.grey.shade100, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lock_rounded,
                    size: 48,
                    color: Colors.indigo.shade600,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  "Community Locked",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.black87,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Join groups, compete on leaderboards, and build habits with friends. Log in to access community features.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo.shade600,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AuthScreen(
                            onLoginSuccess: (authContext) {
                              Navigator.pop(authContext);
                            },
                          ),
                        ),
                      );

                      final user = Supabase.instance.client.auth.currentUser;
                      if (user != null && context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                    child: const Text(
                      "Log In to Continue",
                      style: TextStyle(
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
      ),
    );
  }
}
