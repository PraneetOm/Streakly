import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Needed for ValueListenable
import 'package:hive_flutter/hive_flutter.dart';
import 'package:newapp/screens/hall_of_fame_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/habit.dart';
import 'habit_list_screen.dart';
import 'analytics_screen.dart';
import 'group_list_screen.dart';
import 'auth_screen.dart';
import 'settings_screen.dart';

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

  late ValueListenable<Box<Habit>> _habitListenable;

  @override
  void initState() {
    super.initState();
    
    // Gatekeeper Check
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuthentication();
      _fetchWalletSilent(); // Initial silent fetch
    });

    // 🔥 Real-Time Economy Engine:
    // Any time a habit is updated (XP earned/lost), silently sync the true wallet balance
    _habitListenable = Hive.box<Habit>('habits').listenable();
    _habitListenable.addListener(_fetchWalletSilent);
  }

  @override
  void dispose() {
    _habitListenable.removeListener(_fetchWalletSilent);
    _pageController.dispose();
    super.dispose();
  }

  void _checkAuthentication() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
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

  // 🔥 Silently fetches true DB values and computes "spent coins" for optimistic local math
  Future<void> _fetchWalletSilent() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final res = await supabase
          .from('currencies')
          .select('clockcoins, loose_xp')
          .eq('user_id', userId)
          .maybeSingle();
          
      if (res != null) {
        int dbCoins = res['clockcoins'] ?? 0;
        
        final settingsBox = Hive.box('settings');
        await settingsBox.put('clockcoins', dbCoins);
        await settingsBox.put('loose_xp', res['loose_xp'] ?? 0);
        
        // 🔥 The Magic Trick: Calculate exactly how many coins they've spent historically
        final habitBox = Hive.box<Habit>('habits');
        int totalXP = habitBox.values.fold(0, (sum, h) => sum + h.totalXP);
        int lifetimeCoins = totalXP ~/ 1000;
        
        int spentCoins = max(0, lifetimeCoins - dbCoins);
        await settingsBox.put('spent_coins', spentCoins);
      }
    } catch (e) {
      debugPrint("Silent wallet fetch error: $e");
    }
  }

  // ==========================================
  // 🔥 Interactive Real-Time Wallet Breakdown
  // ==========================================
  void _showWalletDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ValueListenableBuilder(
        // 🔥 Listening to Hive ensures this updates LIVE even while the sheet is open!
        valueListenable: Hive.box<Habit>('habits').listenable(),
        builder: (context, Box<Habit> habitBox, _) {
          return ValueListenableBuilder(
            valueListenable: Hive.box('settings').listenable(keys: ['spent_coins']),
            builder: (context, Box settingsBox, _) {
              
              // 🧮 Optimistic Math (Instant)
              int totalXP = habitBox.values.fold(0, (sum, h) => sum + h.totalXP);
              int lifetimeCoinsMinted = totalXP ~/ 1000;
              int spentCoins = settingsBox.get('spent_coins', defaultValue: 0);
              
              int currentCoins = max(0, lifetimeCoinsMinted - spentCoins);
              int looseXp = totalXP % 1000; // Perfect loose change
              
              int xpToNextCoin = 1000 - looseXp;
              double progressToNextCoin = looseXp / 1000.0;

              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                padding: const EdgeInsets.all(24),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 24),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.account_balance_wallet_rounded, color: Colors.amber.shade600, size: 28),
                          ),
                          const SizedBox(width: 16),
                          const Text(
                            "Your Wallet",
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: Colors.black87,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      
                      // Main Balance Card
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.amber.shade400, Colors.orange.shade500],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orange.withValues(alpha: 0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Available Balance",
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "$currentCoins ClockCoins",
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24),
                                ),
                              ],
                            ),
                            const Icon(Icons.monetization_on_rounded, color: Colors.white, size: 48),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Progress to Next Coin
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Minting Next Coin",
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black87),
                          ),
                          Text(
                            "1,000 XP = 1 🪙",
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.amber),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Every time you earn 1,000 XP, a new ClockCoin is automatically minted. You have $looseXp loose XP right now.",
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.4, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: LinearProgressIndicator(
                          value: progressToNextCoin.clamp(0.0, 1.0),
                          minHeight: 12,
                          backgroundColor: Colors.grey.shade200,
                          color: Colors.amber.shade500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("$looseXp XP", style: TextStyle(color: Colors.amber.shade700, fontWeight: FontWeight.w900, fontSize: 12)),
                          Text("$xpToNextCoin XP needed", style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                      
                      const SizedBox(height: 32),
                      Divider(color: Colors.grey.shade200, height: 1),
                      const SizedBox(height: 24),

                      // Lifetime Stats
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Lifetime Coins", style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text("$lifetimeCoinsMinted", style: TextStyle(color: Colors.indigo.shade700, fontSize: 20, fontWeight: FontWeight.w900)),
                              ],
                            ),
                          ),
                          Container(width: 1, height: 40, color: Colors.grey.shade200),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Coins Spent", style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text("$spentCoins", style: TextStyle(color: Colors.red.shade600, fontSize: 20, fontWeight: FontWeight.w900)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.grey.shade100,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: Text("Close", style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w900, fontSize: 16)),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
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
          // 💰 Optimistic Real-Time Coin Badge (Instantly calculates based on Local XP)
          ValueListenableBuilder(
            valueListenable: Hive.box<Habit>('habits').listenable(),
            builder: (context, Box<Habit> habitBox, _) {
              return ValueListenableBuilder(
                valueListenable: Hive.box('settings').listenable(keys: ['spent_coins']),
                builder: (context, Box settingsBox, _) {
                  
                  // Math is done instantly!
                  int totalXP = habitBox.values.fold(0, (sum, h) => sum + h.totalXP);
                  int lifetimeCoins = totalXP ~/ 1000;
                  int spentCoins = settingsBox.get('spent_coins', defaultValue: 0);
                  
                  int optimisticCoins = max(0, lifetimeCoins - spentCoins);

                  return GestureDetector(
                    onTap: () => _showWalletDetails(context),
                    child: Container(
                      // 🔥 Fatter vertical padding, smaller margin to stretch the height
                      margin: const EdgeInsets.only(top: 8, bottom: 8, left: 4, right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.amber.shade300, Colors.orange.shade500],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.monetization_on_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "$optimisticCoins",
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              fontSize: 15, // Slightly bigger text to match fatter badge
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
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

          // 3-Dot Menu
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
              offset: const Offset(0, 45), 
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

      // Bottom Navigation Bar
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(30),
          ), 
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ), 
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
  }
}

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
          color: Colors.black.withValues(alpha: 0.04),
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