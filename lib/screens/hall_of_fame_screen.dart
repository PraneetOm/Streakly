import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/habit.dart';

class HallOfFameScreen extends StatefulWidget {
  const HallOfFameScreen({super.key});

  @override
  State<HallOfFameScreen> createState() => _HallOfFameScreenState();
}

class _HallOfFameScreenState extends State<HallOfFameScreen> with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _bgController;
  late Animation<Color?> _color1;
  late Animation<Color?> _color2;

  @override
  void initState() {
    super.initState();
    // viewportFraction: 0.8 lets us see the edges of the previous/next cards!
    _pageController = PageController(viewportFraction: 0.82, initialPage: 0);

    // 🔥 A slow, breathing background animation
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);

    _color1 = ColorTween(
      begin: const Color(0xFF0F172A), // Deep Slate
      end: const Color(0xFF1E1B4B), // Deep Indigo
    ).animate(_bgController);

    _color2 = ColorTween(
      begin: const Color(0xFF312E81), // Dark Violet
      end: const Color(0xFF000000), // Pure Black
    ).animate(_bgController);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bgController,
      builder: (context, child) {
        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_color1.value!, _color2.value!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  _buildAppBar(),
                  Expanded(
                    child: ValueListenableBuilder(
                      valueListenable: Hive.box<Habit>('habits').listenable(),
                      builder: (context, Box<Habit> box, _) {
                        final masteredHabits = box.values.where((h) => h.isArchived == true).toList();
                        masteredHabits.sort((a, b) => b.totalXP.compareTo(a.totalXP));

                        if (masteredHabits.isEmpty) {
                          return _buildEmptyState();
                        }

                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Total Stats Summary
                            _buildGlobalStats(masteredHabits),
                            const SizedBox(height: 40),
                            
                            // 🔥 The Collectible Card Carousel
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.55, // 55% of screen height
                              child: PageView.builder(
                                controller: _pageController,
                                physics: const BouncingScrollPhysics(),
                                itemCount: masteredHabits.length,
                                itemBuilder: (context, index) {
                                  return _buildAnimatedCard(masteredHabits[index], index);
                                },
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const Text(
            "THE VAULT",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 4.0,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 48), // Balance the back button
        ],
      ),
    );
  }

  Widget _buildGlobalStats(List<Habit> habits) {
    int totalXP = habits.fold(0, (sum, h) => sum + h.totalXP);
    return Column(
      children: [
        const Text(
          "LIFETIME MASTERED XP",
          style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_awesome_rounded, color: Colors.amber, size: 28),
            const SizedBox(width: 8),
            Text(
              totalXP.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.0,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ==========================================
  // 🔥 THE COVER-FLOW CARD LOGIC
  // ==========================================
  Widget _buildAnimatedCard(Habit habit, int index) {
    return AnimatedBuilder(
      animation: _pageController,
      builder: (context, child) {
        double value = 1.0;
        if (_pageController.position.haveDimensions) {
          value = _pageController.page! - index;
          value = (1 - (value.abs() * 0.25)).clamp(0.0, 1.0); // Scales down adjacent cards by 25%
        } else if (index != 0) {
          value = 0.75; // Initial scale for non-focused cards
        }

        // Apply a subtle rotation along with the scale for a 3D feel
        final double rotation = (1 - value) * 0.5 * (index < (_pageController.page ?? 0) ? -1 : 1);

        return Center(
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001) // Perspective
              ..rotateY(rotation)
              ..scale(value, value),
            child: Opacity(
              opacity: value.clamp(0.4, 1.0), // Fade out side cards slightly
              child: _CollectibleCard(habit: habit),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // A glowing wireframe of a card
        Container(
          width: 220,
          height: 340,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 2),
            gradient: LinearGradient(
              colors: [Colors.white.withValues(alpha: 0.05), Colors.transparent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Icon(Icons.lock_outline_rounded, color: Colors.white.withValues(alpha: 0.2), size: 64),
          ),
        ),
        const SizedBox(height: 40),
        const Text(
          "THE VAULT IS SEALED",
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            "Complete your first habit goal to unlock your first collectible mastery card.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), height: 1.5),
          ),
        ),
      ],
    );
  }
}

// ==========================================
// 🔥 THE COLLECTIBLE CARD WIDGET
// ==========================================
class _CollectibleCard extends StatelessWidget {
  final Habit habit;

  const _CollectibleCard({required this.habit});

  // Determine Card Rarity based on XP
  _CardTheme _getTheme() {
    if (habit.totalXP >= 10000) return _CardTheme(name: "Diamond", colors: [Colors.cyanAccent.shade100, Colors.blue.shade300, Colors.purple.shade300], iconColor: Colors.white);
    if (habit.totalXP >= 3000) return _CardTheme(name: "Gold", colors: [Colors.yellow.shade200, Colors.amber.shade500, Colors.orange.shade700], iconColor: Colors.yellow.shade100);
    if (habit.totalXP >= 1000) return _CardTheme(name: "Silver", colors: [Colors.white, Colors.grey.shade400, Colors.blueGrey.shade700], iconColor: Colors.white);
    return _CardTheme(name: "Bronze", colors: [Colors.orange.shade200, Colors.deepOrange.shade400, Colors.brown.shade600], iconColor: Colors.orange.shade100);
  }

  @override
  Widget build(BuildContext context) {
    final theme = _getTheme();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: theme.colors[1].withValues(alpha: 0.4),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          children: [
            // 1. The metallic gradient background
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: theme.colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            
            // 2. Glassmorphic texture overlay (adds grain/blur)
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                color: Colors.black.withValues(alpha: 0.1),
              ),
            ),

            // 3. Shiny diagonal reflection (makes it look like a physical card)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.0),
                      Colors.white.withValues(alpha: 0.3),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.4, 0.6],
                    begin: const Alignment(-1.0, -1.0),
                    end: const Alignment(1.0, 1.0),
                  ),
                ),
              ),
            ),

            // 4. Inner Content Border
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top Rarity Banner
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          "${theme.name} Tier".toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                        ),
                      ),
                      Icon(Icons.workspace_premium_rounded, color: Colors.white.withValues(alpha: 0.5), size: 20),
                    ],
                  ),
                  
                  const Spacer(),
                  
                  // Center Icon
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: theme.colors[0].withValues(alpha: 0.5), blurRadius: 20),
                        ],
                      ),
                      child: Icon(
                        habit.type.name == 'duration' ? Icons.timer_rounded : Icons.star_rounded, 
                        size: 64, 
                        color: theme.iconColor,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Habit Title
                  Text(
                    habit.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      height: 1.1,
                    ),
                  ),
                  
                  const Spacer(),
                  
                  // Bottom Stats Box
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildCardStat("FINAL XP", "${habit.totalXP}"),
                        Container(width: 1, height: 30, color: Colors.white.withValues(alpha: 0.2)),
                        _buildCardStat("PEAK STREAK", "${habit.streak} d"),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardStat(String label, String value) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _CardTheme {
  final String name;
  final List<Color> colors;
  final Color iconColor;

  _CardTheme({required this.name, required this.colors, required this.iconColor});
}