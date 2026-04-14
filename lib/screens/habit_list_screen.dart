import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/habit.dart';
import '../services/habit_service.dart';
import 'habit_detail_screen.dart';
import '../models/session.dart';
import 'dart:math';
import 'package:flutter/services.dart';

class HabitListScreen extends StatefulWidget {
  const HabitListScreen({super.key});

  @override
  State<HabitListScreen> createState() => _HabitListScreenState();
}

class _HabitListScreenState extends State<HabitListScreen> {
  final HabitService _habitService = HabitService();

  void _showAddHabitDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HabitTemplateSheet(
        onSave: (habit) async {
          await _habitService.addHabit(habit);
          _syncNewHabitToCloudInBackground(habit);
        },
      ),
    );
  }

  Future<void> _syncNewHabitToCloudInBackground(Habit habit) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase.from('habits').insert({
        'id': habit.id,
        'user_id': userId,
        'title': habit.title,
        'type': habit.type.name,
        'daily_target': habit.dailyTarget,
        'unit': habit.unit,
        'xp_per_target': habit.xpPerUnit,
        'created_at': DateTime.now().toIso8601String(),
        'linked_group_ids': habit.linkedGroupIds,
      });

      await supabase.from('streaks').insert({
        'habit_id': habit.id,
        'user_id': userId,
        'current_streak': 0,
        'best_streak': 0,
      });

      debugPrint("✅ New habit & streak initialized in cloud.");
    } catch (e) {
      debugPrint("❌ Failed to sync new habit to cloud: $e");
    }
  }

  // ==========================================
  // 🔥 NEW: Adjust Wallet on Delete
  // ==========================================
  Future<void> _adjustCurrency(int xpDelta) async {
    if (xpDelta == 0) return;

    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final currencyData = await supabase
          .from('currencies')
          .select('clockcoins, loose_xp')
          .eq('user_id', userId)
          .maybeSingle();

      int currentCoins = currencyData?['clockcoins'] as int? ?? 0;
      int currentLoose = currencyData?['loose_xp'] as int? ?? 0;

      int currentNetWorth = (currentCoins * 1000) + currentLoose;
      int newNetWorth = max(0, currentNetWorth + xpDelta);

      int newCoins = newNetWorth ~/ 1000;
      int newLoose = newNetWorth % 1000;

      await supabase
          .from('currencies')
          .update({
            'clockcoins': newCoins,
            'loose_xp': newLoose,
            'last_updated': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('user_id', userId);

      debugPrint(
        "💸 Economy Adjusted on Delete: $xpDelta XP. New Balance: $newCoins Coins.",
      );
    } catch (e) {
      debugPrint("❌ Failed to adjust currency on delete: $e");
    }
  }

  void _confirmDelete(Habit habit) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.delete_sweep_rounded,
                color: Colors.red.shade600,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                "Delete Habit?",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ),
          ],
        ),
        content: Text(
          "Are you sure you want to delete '${habit.title}'? This will permanently remove its streak, history, and deduct ${habit.totalXP} XP from your total balance.",
          style: TextStyle(color: Colors.grey.shade700, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Cancel",
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            // 🔥 Make this onPressed async
            onPressed: () async {
              int xpToDeduct = habit.totalXP;

              // 1. Instant Local Delete of the Habit
              _habitService.deleteHabit(habit.id);

              // 🔥 THE FIX: Wipe all orphaned local sessions for this habit!
              final sessionBox = Hive.box<Sessions>('sessions');
              final orphanedKeys = sessionBox
                  .toMap()
                  .entries
                  .where((entry) => entry.value.habitId == habit.id)
                  .map((entry) => entry.key)
                  .toList();
              await sessionBox.deleteAll(orphanedKeys);

              if (mounted) Navigator.pop(context);

              // 2. Securely deduct XP from the global economy
              _adjustCurrency(-xpToDeduct);

              // 3. Background Cloud Delete
              _deleteFromCloudInBackground(habit.id);
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFromCloudInBackground(String habitId) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) return;

    try {
      // 1. Delete child records first to prevent Foreign Key constraints
      await supabase.from('habit_sessions').delete().eq('habit_id', habitId);
      await supabase.from('streaks').delete().eq('habit_id', habitId);

      // 🔥 NEW: Also wipe any group activity tied to this habit
      await supabase.from('group_activity').delete().eq('habit_id', habitId);

      // 2. Delete the parent habit
      await supabase.from('habits').delete().eq('id', habitId);

      debugPrint("✅ Habit and related data permanently deleted from cloud.");
    } catch (e) {
      debugPrint("❌ Failed to delete habit from cloud: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<Habit>('habits');
    final settingsBox = Hive.box('settings');

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box<Habit> box, _) {
          List<dynamic> savedOrder = settingsBox.get(
            'habit_order',
            defaultValue: [],
          );

          final activeHabits = box.values
              .where((habit) => habit.isArchived == false)
              .toList();

          activeHabits.sort((a, b) {
            int indexA = savedOrder.indexOf(a.id);
            int indexB = savedOrder.indexOf(b.id);
            if (indexA == -1) indexA = 999999;
            if (indexB == -1) indexB = 999999;
            return indexA.compareTo(indexB);
          });

          int totalXP = box.values.fold(0, (sum, h) => sum + h.totalXP);

          final sessionBox = Hive.box<Sessions>('sessions');
          final sessions = sessionBox.values.toList();

          Map<String, int> weeklyXP = {};
          for (int i = 6; i >= 0; i--) {
            final day = DateTime.now().subtract(Duration(days: i));
            final key = "${day.year}-${day.month}-${day.day}";
            weeklyXP[key] = 0;
          }

          for (var session in sessions) {
            final key =
                "${session.date.year}-${session.date.month}-${session.date.day}";
            if (weeklyXP.containsKey(key)) {
              weeklyXP[key] = weeklyXP[key]! + session.xpEarned;
            }
          }

          int level = (sqrt(totalXP / 80)).floor() + 1;
          int currentLevelBaseXP = pow(level - 1, 2).toInt() * 80;
          int nextLevelXP = pow(level, 2).toInt() * 80;

          int xpIntoCurrentLevel = totalXP - currentLevelBaseXP;
          int xpNeededForNextLevel = nextLevelXP - currentLevelBaseXP;

          double currentLevelProgress = xpNeededForNextLevel == 0
              ? 0
              : xpIntoCurrentLevel / xpNeededForNextLevel;

          final runningHabit = activeHabits.where((h) => h.isRunning).isNotEmpty
              ? activeHabits.firstWhere((h) => h.isRunning)
              : null;

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 56, 16, 8),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.indigo.shade400,
                            Colors.indigo.shade800,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.indigo.withValues(alpha: 0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Level $level",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 34,
                                        fontWeight: FontWeight.w900,
                                        height: 1.1,
                                        letterSpacing: -1.0,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "$xpIntoCurrentLevel XP collected",
                                      style: TextStyle(
                                        color: Colors.indigo.shade100,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  "${activeHabits.length} Active Habits",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: currentLevelProgress.clamp(0.0, 1.0),
                              minHeight: 12,
                              backgroundColor: Colors.black.withValues(
                                alpha: 0.15,
                              ),
                              color: Colors.greenAccent.shade400,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Progress to Lv ${level + 1}",
                                style: TextStyle(
                                  color: Colors.indigo.shade100,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                "${nextLevelXP - totalXP} XP left",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.insights_rounded,
                                    color: Colors.indigo.shade400,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Daily Pulse",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                "Last 7 Days",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          Builder(
                            builder: (context) {
                              int maxXP = weeklyXP.values.isEmpty
                                  ? 1
                                  : weeklyXP.values.reduce(max);
                              if (maxXP == 0) {
                                maxXP = 1;
                              }
                              return Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: weeklyXP.entries.map((entry) {
                                  int xp = entry.value;
                                  double fillPercentage = xp / maxXP;
                                  double barHeight = fillPercentage * 90;
                                  if (xp > 0 && barHeight < 8) {
                                    barHeight = 8;
                                  }

                                  final dateParts = entry.key.split("-");
                                  DateTime dateObj = DateTime(
                                    int.parse(dateParts[0]),
                                    int.parse(dateParts[1]),
                                    int.parse(dateParts[2]),
                                  );
                                  String dayName = [
                                    'M',
                                    'T',
                                    'W',
                                    'T',
                                    'F',
                                    'S',
                                    'S',
                                  ][dateObj.weekday - 1];

                                  return Expanded(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            xp > 0 ? "$xp" : "",
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.indigo.shade700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          height: 90,
                                          width: 28,
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          alignment: Alignment.bottomCenter,
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 600,
                                            ),
                                            curve: Curves.easeOutCubic,
                                            height: barHeight,
                                            width: 28,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              gradient: LinearGradient(
                                                colors: xp > 0
                                                    ? [
                                                        Colors.indigo.shade300,
                                                        Colors.indigo.shade600,
                                                      ]
                                                    : [
                                                        Colors.transparent,
                                                        Colors.transparent,
                                                      ],
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          dayName,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: xp > 0
                                                ? Colors.black87
                                                : Colors.grey.shade400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    if (runningHabit != null)
                      Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.green.shade200,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.timer_outlined,
                                color: Colors.green.shade700,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Currently Running",
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                  Text(
                                    runningHabit.title,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      color: Colors.green.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade600,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        HabitDetailScreen(habit: runningHabit),
                                  ),
                                );
                              },
                              child: const Text(
                                "View",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              if (activeHabits.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_task_rounded,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "No habits yet",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Tap + to start building better routines.",
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 8,
                    bottom: 100,
                  ),
                  sliver: SliverReorderableList(
                    itemCount: activeHabits.length,
                    itemBuilder: (context, index) {
                      final habit = activeHabits[index];
                      return Container(
                        key: ValueKey(habit.id),
                        child: _buildHabitCard(habit, index),
                      );
                    },
                    onReorder: (int oldIndex, int newIndex) {
                      setState(() {
                        if (oldIndex < newIndex) {
                          newIndex -= 1;
                        }
                        final habit = activeHabits.removeAt(oldIndex);
                        activeHabits.insert(newIndex, habit);

                        settingsBox.put(
                          'habit_order',
                          activeHabits.map((h) => h.id).toList(),
                        );
                      });
                    },
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddHabitDialog,
        backgroundColor: Colors.indigo.shade600,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.add),
        label: const Text(
          "New Habit",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildHabitCard(Habit habit, int index) {
    String scheduleLabel() {
      if (habit.frequency == HabitFrequency.daily) return "Daily";
      if (habit.frequency == HabitFrequency.weekly) return "Weekly";
      if (habit.frequency == HabitFrequency.custom &&
          habit.customDays != null) {
        final labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        return habit.customDays!.map((d) => labels[d - 1]).join(', ');
      }
      return "";
    }

    IconData getIconForType() {
      switch (habit.type) {
        case HabitType.duration:
          return Icons.timer_rounded;
        case HabitType.count:
          return Icons.repeat_rounded;
        case HabitType.quantity:
          return Icons.water_drop_rounded;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ValueListenableBuilder(
          valueListenable: Hive.box<Sessions>('sessions').listenable(),
          builder: (context, Box<Sessions> sessionBox, _) {
            final today = DateTime.now();
            double todayTotal = 0;

            for (var s in sessionBox.values) {
              if (s.habitId == habit.id &&
                  s.date.year == today.year &&
                  s.date.month == today.month &&
                  s.date.day == today.day) {
                todayTotal += s.value;
              }
            }

            double progress = habit.dailyTarget > 0
                ? todayTotal / habit.dailyTarget
                : 0;
            bool isCompleted = progress >= 1.0;

            String formattedTotal = todayTotal.toStringAsFixed(
              todayTotal.truncateToDouble() == todayTotal ? 0 : 1,
            );
            String formattedTarget = habit.dailyTarget.toStringAsFixed(
              habit.dailyTarget.truncateToDouble() == habit.dailyTarget ? 0 : 1,
            );

            return Stack(
              children: [
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isCompleted
                              ? [
                                  Colors.green.shade50,
                                  Colors.green.shade100.withValues(alpha: 0.5),
                                ]
                              : [
                                  Colors.indigo.shade50.withValues(alpha: 0.5),
                                  Colors.indigo.shade50,
                                ],
                        ),
                      ),
                    ),
                  ),
                ),

                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HabitDetailScreen(habit: habit),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isCompleted
                                  ? Colors.green.withValues(alpha: 0.1)
                                  : Colors.indigo.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              isCompleted
                                  ? Icons.check_circle_rounded
                                  : getIconForType(),
                              color: isCompleted
                                  ? Colors.green.shade600
                                  : Colors.indigo.shade500,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  habit.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.local_fire_department_rounded,
                                      size: 14,
                                      color: Colors.orange.shade500,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      "${habit.streak}",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Icon(
                                      Icons.star_rounded,
                                      size: 14,
                                      color: Colors.amber.shade500,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      "${habit.totalXP}",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),

                                    if (habit.linkedGroupIds.isNotEmpty) ...[
                                      const SizedBox(width: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.indigo.shade50,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: Border.all(
                                            color: Colors.indigo.shade100,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.groups_rounded,
                                              size: 12,
                                              color: Colors.indigo.shade600,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              "${habit.linkedGroupIds.length}",
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.indigo.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),

                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isCompleted
                                    ? Colors.green.shade200
                                    : Colors.indigo.shade100,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!isCompleted) ...[
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      value: progress,
                                      strokeWidth: 2.5,
                                      backgroundColor: Colors.grey.shade200,
                                      color: Colors.indigo.shade400,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Text(
                                  isCompleted
                                      ? "DONE"
                                      : "$formattedTotal / $formattedTarget",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: isCompleted
                                        ? Colors.green.shade700
                                        : Colors.indigo.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 4),
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              color: Colors.red.shade300,
                              size: 20,
                            ),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(8),
                            onPressed: () => _confirmDelete(habit),
                          ),
                          ReorderableDragStartListener(
                            index: index,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: 4,
                                right: 4,
                                top: 12,
                                bottom: 12,
                              ),
                              child: Icon(
                                Icons.drag_handle_rounded,
                                color: Colors.grey.shade400,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ==========================================
// 🔥 Redesigned Add Habit Bottom Sheet
// ==========================================

class _HabitTemplateSheet extends StatefulWidget {
  final Function(Habit) onSave;
  const _HabitTemplateSheet({required this.onSave});

  @override
  State<_HabitTemplateSheet> createState() => _HabitTemplateSheetState();
}

class _HabitTemplateSheetState extends State<_HabitTemplateSheet> {
  final _uuid = const Uuid();
  final _formKey = GlobalKey<FormState>();

  final titleController = TextEditingController();
  final targetController = TextEditingController();
  final unitController = TextEditingController(text: "minutes");

  HabitType selectedType = HabitType.duration;
  HabitFrequency selectedFrequency = HabitFrequency.daily;

  List<bool> selectedWeekdays = List.generate(7, (_) => false);
  String activeTemplate = "Custom";

  int _difficulty = 1;

  bool _isLoadingGroups = true;
  List<Map<String, dynamic>> _myGroups = [];
  final List<String> _selectedGroupIds = [];

  @override
  void initState() {
    super.initState();
    _fetchMyGroups();
  }

  Future<void> _fetchMyGroups() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await supabase
          .from('group_members')
          .select('group_id, groups(name)')
          .eq('user_id', userId)
          .eq('status', 'active');

      final List<Map<String, dynamic>> groups = [];
      for (var row in response) {
        if (row['groups'] != null) {
          groups.add({'id': row['group_id'], 'name': row['groups']['name']});
        }
      }

      if (mounted) {
        setState(() {
          _myGroups = groups;
          _isLoadingGroups = false;
        });
      }
    } catch (e) {
      debugPrint("Failed to fetch groups: $e");
      if (mounted) setState(() => _isLoadingGroups = false);
    }
  }

  void _applyTemplate(String template) {
    setState(() {
      activeTemplate = template;
      switch (template) {
        case 'Study':
          selectedType = HabitType.duration;
          titleController.text = "Study";
          unitController.text = "minutes";
          targetController.text = "60";
          _difficulty = 1; // Medium
          break;
        case 'Water':
          selectedType = HabitType.quantity;
          titleController.text = "Drink Water";
          unitController.text = "litres";
          targetController.text = "2";
          _difficulty = 0; // Easy
          break;
        case 'Workout':
          selectedType = HabitType.count;
          titleController.text = "Workout";
          unitController.text = "reps";
          targetController.text = "50";
          _difficulty = 2; // Hard
          break;
        case 'Reading':
          selectedType = HabitType.count;
          titleController.text = "Reading";
          unitController.text = "pages";
          targetController.text = "20";
          _difficulty = 1; // Medium
          break;
        case 'Custom':
          selectedType = HabitType.duration;
          titleController.clear();
          unitController.text = "units";
          targetController.clear();
          _difficulty = 1;
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Map<HabitType, List<String>> unitSuggestions = {
      HabitType.duration: ["seconds", "minutes", "hours"],
      HabitType.count: ["reps", "times", "sets", "pages", "tasks"],
      HabitType.quantity: ["litres", "glasses", "km", "steps"],
    };

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Create New Habit",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Quick Templates",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children:
                            [
                              "Study",
                              "Water",
                              "Workout",
                              "Reading",
                              "Custom",
                            ].map((label) {
                              final isSelected = activeTemplate == label;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(
                                    label,
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.black87,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  selected: isSelected,
                                  selectedColor: Colors.indigo,
                                  backgroundColor: Colors.grey.shade100,
                                  side: BorderSide.none,
                                  onSelected: (_) => _applyTemplate(label),
                                ),
                              );
                            }).toList(),
                      ),
                    ),
                    const SizedBox(height: 24),

                    const Text(
                      "Habit Type",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: HabitType.values.map((type) {
                        IconData icon;
                        String title;
                        switch (type) {
                          case HabitType.duration:
                            icon = Icons.timer_rounded;
                            title = "Timer";
                            break;
                          case HabitType.count:
                            icon = Icons.repeat_rounded;
                            title = "Count";
                            break;
                          case HabitType.quantity:
                            icon = Icons.water_drop_rounded;
                            title = "Quantity";
                            break;
                        }
                        final isSelected = selectedType == type;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                selectedType = type;
                                if (unitSuggestions[type]!.isNotEmpty) {
                                  unitController.text =
                                      unitSuggestions[type]!.first;
                                }
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.indigo.shade50
                                    : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.indigo.shade300
                                      : Colors.grey.shade200,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    icon,
                                    color: isSelected
                                        ? Colors.indigo
                                        : Colors.grey.shade500,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    title,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? Colors.indigo
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),

                    _buildInputField(
                      controller: titleController,
                      label: "Habit Name",
                      icon: Icons.title_rounded,
                      maxLength: 35,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return "Enter a habit name";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    if (selectedType == HabitType.duration)
                      DropdownButtonFormField<String>(
                        initialValue: unitController.text.isEmpty
                            ? "minutes"
                            : unitController.text,
                        decoration: InputDecoration(
                          labelText: "Measurement Unit",
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          prefixIcon: const Icon(Icons.straighten_rounded),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: "seconds",
                            child: Text("Seconds"),
                          ),
                          DropdownMenuItem(
                            value: "minutes",
                            child: Text("Minutes"),
                          ),
                          DropdownMenuItem(
                            value: "hours",
                            child: Text("Hours"),
                          ),
                        ],
                        onChanged: (val) =>
                            setState(() => unitController.text = val!),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildInputField(
                            controller: unitController,
                            label: "Measurement Unit (e.g. pages, km)",
                            icon: Icons.straighten_rounded,
                            maxLength: 35,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return "Enter unit";
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: unitSuggestions[selectedType]!
                                .map(
                                  (unit) => ActionChip(
                                    label: Text(
                                      unit,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    backgroundColor: Colors.grey.shade100,
                                    side: BorderSide.none,
                                    onPressed: () => setState(
                                      () => unitController.text = unit,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),

                    const SizedBox(height: 16),
                    _buildInputField(
                      controller: targetController,
                      label: "Daily Target",
                      icon: Icons.flag_rounded,
                      isNumber: true,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "Enter target";
                        }

                        final num = double.tryParse(value);
                        if (num == null) {
                          return "Invalid number";
                        }

                        if (num <= 0) {
                          return "Must be greater than 0";
                        }

                        if (num > 100000) {
                          return "Too large";
                        }

                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    const Text(
                      "Difficulty Level",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _buildDifficultyOption(
                          0,
                          "Easy",
                          Icons.spa_rounded,
                          Colors.green,
                        ),
                        _buildDifficultyOption(
                          1,
                          "Medium",
                          Icons.whatshot_rounded,
                          Colors.orange,
                        ),
                        _buildDifficultyOption(
                          2,
                          "Hard",
                          Icons.local_fire_department_rounded,
                          Colors.red,
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 4),
                      child: Text(
                        "Rewards: Up to ${_difficulty == 0 ? '50' : (_difficulty == 1 ? '100' : '150')} XP for hitting your daily target",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    if (_myGroups.isNotEmpty) ...[
                      const Text(
                        "Link to Groups",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "XP from this habit will only be shared with selected groups.",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      _isLoadingGroups
                          ? const Center(child: CircularProgressIndicator())
                          : Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _myGroups.map((group) {
                                final isSelected = _selectedGroupIds.contains(
                                  group['id'],
                                );
                                return FilterChip(
                                  label: Text(
                                    group['name'],
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: isSelected
                                          ? Colors.indigo.shade700
                                          : Colors.black87,
                                    ),
                                  ),
                                  selected: isSelected,
                                  selectedColor: Colors.indigo.shade50,
                                  checkmarkColor: Colors.indigo.shade600,
                                  backgroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: isSelected
                                          ? Colors.indigo.shade300
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  onSelected: (selected) {
                                    setState(() {
                                      if (selected) {
                                        _selectedGroupIds.add(group['id']);
                                      } else {
                                        _selectedGroupIds.remove(group['id']);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                      const SizedBox(height: 24),
                    ],

                    const Text(
                      "Schedule",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<HabitFrequency>(
                      initialValue: selectedFrequency,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: const Icon(Icons.calendar_month_rounded),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: HabitFrequency.daily,
                          child: Text("Everyday"),
                        ),
                        DropdownMenuItem(
                          value: HabitFrequency.weekly,
                          child: Text("Weekly target"),
                        ),
                        DropdownMenuItem(
                          value: HabitFrequency.custom,
                          child: Text("Specific Days"),
                        ),
                      ],
                      onChanged: (v) => setState(() => selectedFrequency = v!),
                    ),

                    if (selectedFrequency == HabitFrequency.custom) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: List.generate(7, (i) {
                          final labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                          return FilterChip(
                            selected: selectedWeekdays[i],
                            label: Text(labels[i]),
                            selectedColor: Colors.indigo.shade100,
                            checkmarkColor: Colors.indigo,
                            onSelected: (sel) =>
                                setState(() => selectedWeekdays[i] = sel),
                          );
                        }),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    if (!_formKey.currentState!.validate()) {
                      return;
                    }

                    final selectedCustomDays = <int>[];
                    for (int i = 0; i < selectedWeekdays.length; i++) {
                      if (selectedWeekdays[i]) selectedCustomDays.add(i + 1);
                    }

                    double target = double.tryParse(targetController.text) ?? 1;

                    target = target.clamp(1, 100000);

                    double targetXpPool = _difficulty == 0
                        ? 50.0
                        : (_difficulty == 1 ? 100.0 : 150.0);
                    double calculatedXpPerUnit = targetXpPool / target;

                    final habitBox = Hive.box<Habit>('habits');
                    final existing = habitBox.values.where(
                      (h) =>
                          h.title.toLowerCase().trim() ==
                          titleController.text.toLowerCase().trim(),
                    );

                    if (existing.isNotEmpty) {
                      ScaffoldMessenger.of(
                        Navigator.of(context).context,
                      ).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "A habit with this name already exists",
                          ),
                        ),
                      );
                      return;
                    }

                    final habit = Habit(
                      id: _uuid.v4(),
                      title: titleController.text,
                      type: selectedType,
                      unit: unitController.text,
                      dailyTarget: target,
                      xpPerUnit: calculatedXpPerUnit,
                      frequency: selectedFrequency,
                      customDays: selectedCustomDays.isEmpty
                          ? null
                          : selectedCustomDays,
                      linkedGroupIds: _selectedGroupIds,
                    );

                    widget.onSave(habit);
                    Navigator.pop(context);
                  },
                  child: const Text(
                    "Save Habit",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isNumber = false,
    int? maxLength,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLength: maxLength,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      keyboardType: isNumber
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: isNumber
          ? [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))]
          : [],
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade500),
        prefixIcon: Icon(icon, color: Colors.grey.shade400),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildDifficultyOption(
    int index,
    String label,
    IconData icon,
    MaterialColor color,
  ) {
    bool isSelected = _difficulty == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _difficulty = index),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color.shade50 : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color.shade300 : Colors.grey.shade200,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? color.shade600 : Colors.grey.shade400,
                size: 22,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? color.shade700 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}