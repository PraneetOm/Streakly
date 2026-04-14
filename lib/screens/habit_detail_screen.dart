import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:newapp/services/group_service.dart';
import '../models/habit.dart';
import '../models/session.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HabitDetailScreen extends StatefulWidget {
  final Habit habit;

  const HabitDetailScreen({super.key, required this.habit});

  @override
  State<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends State<HabitDetailScreen> {
  Timer? _uiTimer;
  double _currentValue = 0;
  OverlayEntry? _xpOverlay;

  final TextEditingController _valueController = TextEditingController();
  final FocusNode _valueFocus = FocusNode();

  // 🔥 DEFINED STREAK MILESTONES & REWARDS
  final Map<int, int> _milestones = {
    3: 50,
    7: 100,
    14: 150,
    21: 200,
    30: 500,
    50: 1000,
    100: 1750,
    365: 20000,
  };

  @override
  void initState() {
    super.initState();
    _valueController.text = "0";

    if (widget.habit.isRunning) {
      _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() {});
      });
    }
  }

  double _getTodayProgress() {
    final sessionBox = Hive.box<Sessions>('sessions');
    final today = DateTime.now();

    final sessions = sessionBox.values.where((session) {
      return session.habitId == widget.habit.id &&
          session.date.year == today.year &&
          session.date.month == today.month &&
          session.date.day == today.day;
    });

    double total = 0;
    for (var s in sessions) {
      total += s.value;
    }
    return total;
  }

  int get _elapsedSeconds {
    if (!widget.habit.isRunning || widget.habit.startTime == null) return 0;
    return DateTime.now().difference(widget.habit.startTime!).inSeconds;
  }

  // 🔥 NEW: Calculates XP based on percentage completed, ignoring corrupted data
  int _calculateSafeBaseXp(double value) {
    double currentPool = widget.habit.xpPerUnit * widget.habit.dailyTarget;
    double actualPool = 100.0;

    if (currentPool > 0 && currentPool <= 55) {
      actualPool = 50.0;
    } else if (currentPool > 55 && currentPool <= 105) {
      actualPool = 100.0;
    } else if (currentPool > 105 && currentPool <= 250) {
      actualPool = 150.0;
    }

    double progressFraction = value / widget.habit.dailyTarget;
    return (progressFraction * actualPool).round().clamp(0, 50000);
  }

  void _startTimer() async {
    widget.habit.isRunning = true;
    widget.habit.startTime = DateTime.now();
    await widget.habit.save();

    _uiTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
    setState(() {});
  }

  void _stopTimer() async {
    _uiTimer?.cancel();
    _uiTimer = null;
    double value;

    if (widget.habit.type == HabitType.duration) {
      switch (widget.habit.unit) {
        case "seconds":
          value = _elapsedSeconds.toDouble();
          break;
        case "minutes":
          value = _elapsedSeconds / 60;
          break;
        case "hours":
          value = _elapsedSeconds / 3600;
          break;
        default:
          value = _elapsedSeconds / 60;
      }
    } else {
      value = 1;
    }

    int baseXp = _calculateSafeBaseXp(value);
    widget.habit.isRunning = false;
    widget.habit.startTime = null;

    int bonusXp = await _updateLocalHabitProgress(baseXp);
    int totalXpEarned = baseXp + bonusXp;

    final session = Sessions(
      habitId: widget.habit.id,
      value: value,
      date: DateTime.now(),
      xpEarned: totalXpEarned,
    );
    await Hive.box<Sessions>('sessions').add(session);

    if (bonusXp > 0) {
      _showMilestoneCelebration(widget.habit.streak, bonusXp);
    } else {
      _showXpPopup(totalXpEarned);
    }
    setState(() {});

    _syncToCloudInBackground(session, totalXpEarned);
  }

  void _saveCountQuantity() async {
    FocusScope.of(context).unfocus();
    
    // 🔥 THE FIX: Clamp the actual input value so it cannot exceed 99,999 per session
    double value = _currentValue.clamp(0.0, 99999.0);
    if (value <= 0) return;

    int baseXp = _calculateSafeBaseXp(value);
    int bonusXp = await _updateLocalHabitProgress(baseXp);
    int totalXpEarned = baseXp + bonusXp;

    final session = Sessions(
      habitId: widget.habit.id,
      value: value,
      date: DateTime.now(),
      xpEarned: totalXpEarned,
    );
    await Hive.box<Sessions>('sessions').add(session);

    setState(() {
      _currentValue = 0;
      _valueController.text = "0";
    });

    if (bonusXp > 0) {
      _showMilestoneCelebration(widget.habit.streak, bonusXp);
    } else {
      _showXpPopup(totalXpEarned);
    }

    _syncToCloudInBackground(session, totalXpEarned);
  }

  Future<int> _updateLocalHabitProgress(int baseXp) async {
    final habit = widget.habit;
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));

    int totalCoinsBefore = habit.totalXP ~/ 1000;
    bool missedDay = false;
    bool streakIncreased = false;

    if (habit.lastCompletedDate != null) {
      final last = habit.lastCompletedDate!;
      if (_isSameDay(last, today)) {
        // Already counted today
      } else if (_isSameDay(last, yesterday)) {
        habit.streak += 1;
        streakIncreased = true;
      } else {
        missedDay = true;
      }
    } else {
      habit.streak = 1;
      streakIncreased = true;
    }

    if (missedDay) {
      if (totalCoinsBefore >= 1) {
        bool? useCoin = await _showInsuranceDialog();
        if (useCoin == true) {
          habit.totalXP -= 100;
          habit.streak += 1;
          streakIncreased = true;
        } else {
          habit.streak = 1;
          streakIncreased = true;
        }
      } else {
        habit.streak = 1;
        streakIncreased = true;
      }
    }

    int earnedBonus = 0;
    if (streakIncreased && _milestones.containsKey(habit.streak)) {
      earnedBonus = _milestones[habit.streak]!;
    }

    habit.lastCompletedDate = today;
    habit.totalXP += (baseXp + earnedBonus);
    await habit.save();

    return earnedBonus;
  }

  // 🔥 NEW: Session Deletion & Undo Function
  Future<void> _deleteSessionLog(dynamic sessionKey, Sessions session) async {
    // 1. Deduct XP from Habit (Preventing negative XP)
    widget.habit.totalXP = max(0, widget.habit.totalXP - session.xpEarned);
    await widget.habit.save();

    // 2. Delete local session record
    await Hive.box<Sessions>('sessions').delete(sessionKey);
    setState(() {}); // Refresh UI

    // 3. Inform user
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Log removed. ${session.xpEarned} XP deducted."),
          backgroundColor: Colors.grey.shade800,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    // 4. Delete from Supabase in background
    try {
      final supabase = Supabase.instance.client;
      await supabase
          .from('habit_sessions')
          .delete()
          .eq('habit_id', widget.habit.id)
          .eq('started_at', session.date.toIso8601String());
    } catch (e) {
      debugPrint("Failed to delete session from cloud: $e");
    }
  }

  // 🔥 NEW: Edit an existing session log and safely recalculate XP
  Future<void> _editSessionLog(dynamic sessionKey, Sessions session) async {
    final editCtrl = TextEditingController(
      text: session.value.toStringAsFixed(session.value.truncateToDouble() == session.value ? 0 : 1)
    );

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Edit Progress", style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: editCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            LengthLimitingTextInputFormatter(7),
            FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
          ],
          decoration: InputDecoration(
            labelText: "New Value (${widget.habit.unit})",
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), 
            child: Text("Cancel", style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo.shade600, 
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
            ),
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("Save")
          ),
        ],
      )
    );

    if (confirm == true) {
      double newValue = double.tryParse(editCtrl.text) ?? session.value;
      newValue = newValue.clamp(0.0, 99999.0);

      if (newValue == session.value) return; // No change
      if (newValue <= 0) {
        _deleteSessionLog(sessionKey, session); // If they edit to 0, just delete it
        return;
      }

      // Calculate the difference in Base XP, preserving any streak bonus they earned that day
      int oldBaseXp = _calculateSafeBaseXp(session.value);
      int newBaseXp = _calculateSafeBaseXp(newValue);
      int bonusXp = session.xpEarned - oldBaseXp; 
      int newTotalXpEarned = newBaseXp + bonusXp;

      // Safely update Habit Total XP
      widget.habit.totalXP = max(0, widget.habit.totalXP - session.xpEarned + newTotalXpEarned);
      await widget.habit.save();

      // Update Session
      session.value = newValue;
      session.xpEarned = newTotalXpEarned;
      await Hive.box<Sessions>('sessions').put(sessionKey, session);
      
      setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Log updated to $newValue ${widget.habit.unit}."),
            backgroundColor: Colors.indigo.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // Sync the fixed flow_points to the cloud
      try {
        final supabase = Supabase.instance.client;
        await supabase.from('habit_sessions')
            .update({'flow_points': session.xpEarned})
            .eq('habit_id', widget.habit.id)
            .eq('started_at', session.date.toIso8601String());
      } catch (e) {
        debugPrint("Cloud update failed: $e");
      }
    }
  }

  Future<bool?> _showInsuranceDialog() {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          "Streak at Risk!",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "You missed yesterday.\nUse 1 ClockCoin to save your streak?",
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              "No thanks",
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              "Use Coin",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

// 🔥 UPGRADED: Short, Punchy Archive Dialog
  Future<void> _archiveHabit() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
                  child: Icon(Icons.task_alt_rounded, color: Colors.green.shade600, size: 28),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    "Finish Goal?",
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Colors.black87),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // TL;DR Bullet Points
            _buildDialogBullet("Removes habit from daily list"),
            _buildDialogBullet("Safely stores all earned XP"),
            _buildDialogBullet("Locks in your peak streak"),
            
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: Text("Cancel", style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text("Complete", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      // 1. Update Local Hive Model
      widget.habit.isArchived = true;
      await widget.habit.save();

      // 2. Sync to Supabase
      try {
        final supabase = Supabase.instance.client;
        await supabase
            .from('habits')
            .update({'isArchived': true})
            .eq('id', widget.habit.id);
      } catch (e) {
        debugPrint("Failed to sync archive status to cloud: $e");
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white),
                SizedBox(width: 12),
                Text(
                  "Habit Completed! XP Safely Stored.",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            margin: const EdgeInsets.all(20),
          ),
        );
        Navigator.pop(context); // Send them safely back to the home screen
      }
    }
  }

  Widget _buildDialogBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline_rounded, color: Colors.green.shade400, size: 18),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(color: Colors.grey.shade700, fontSize: 14, fontWeight: FontWeight.w500, height: 1.3))),
        ],
      ),
    );
  }

  Future<void> _syncToCloudInBackground(Sessions session, int xpEarned) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase.from('habits').upsert({
        'id': widget.habit.id,
        'user_id': userId,
        'title': widget.habit.title,
        'type': widget.habit.type.name,
      });

      await supabase.from('habit_sessions').insert({
        'habit_id': session.habitId,
        'user_id': userId,
        'started_at': session.date.toUtc().toIso8601String(),
        'ended_at': session.date.toUtc().toIso8601String(),
        'flow_points': session.xpEarned,
        'success': true,
        'value': session.value,
      });

      final streakData = await supabase
          .from('streaks')
          .select('id, best_streak')
          .eq('habit_id', widget.habit.id)
          .eq('user_id', userId)
          .maybeSingle();

      int currentStreak = widget.habit.streak;
      int bestStreak = currentStreak;

      if (streakData != null) {
        int dbBestStreak = streakData['best_streak'] as int? ?? 0;
        bestStreak = currentStreak > dbBestStreak
            ? currentStreak
            : dbBestStreak;

        await supabase
            .from('streaks')
            .update({
              'current_streak': currentStreak,
              'best_streak': bestStreak,
              'last_completed_date': widget.habit.lastCompletedDate
                  ?.toIso8601String(),
            })
            .eq('id', streakData['id']);
      } else {
        await supabase.from('streaks').insert({
          'habit_id': widget.habit.id,
          'user_id': userId,
          'current_streak': currentStreak,
          'best_streak': bestStreak,
          'last_completed_date': widget.habit.lastCompletedDate
              ?.toIso8601String(),
        });
      }

      final groupService = GroupService();
      final allGroups = await groupService.getUserGroups(userId);

      // 🔥 THE FIX: Route XP ONLY to the groups this habit is explicitly linked to!
      final linkedGroups = allGroups.where(
        (g) => widget.habit.linkedGroupIds.contains(g['group_id'])
      ).toList();
      
      if (linkedGroups.isEmpty) return; // Halt if not shared with any groups

      final actorName = await groupService.getMyDisplayName(userId);

      await Future.wait(
        linkedGroups.map((g) async {
          final groupId = g['group_id'];
          final beforeRank = await groupService.getUserRank(groupId, userId);

          await groupService.addXPToUser(
            groupId: groupId,
            userId: userId,
            xp: xpEarned,
          );
          final afterRank = await groupService.getUserRank(groupId, userId);

          await groupService.addGroupActivity(
            groupId: groupId,
            actorUserId: userId,
            actorName: actorName,
            activityType: 'habit_completed',
            title: '$actorName completed ${widget.habit.title}',
            body: 'Earned $xpEarned XP',
            value: session.value,
            xpEarned: xpEarned,
            oldRank: beforeRank,
            newRank: afterRank,
            habitId: widget.habit.id,
          );

          if (beforeRank != null &&
              afterRank != null &&
              beforeRank != afterRank) {
            await groupService.addGroupActivity(
              groupId: groupId,
              actorUserId: userId,
              actorName: actorName,
              activityType: 'rank_changed',
              title: '$actorName leveled up!',
              body: 'Moved from #$beforeRank to #$afterRank',
              xpEarned: 0,
              oldRank: beforeRank,
              newRank: afterRank,
              habitId: widget.habit.id,
            );
          }
        }),
      );
    } catch (e) {
      debugPrint("❌ Background sync failed: $e");
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6F9),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black87),
          title: Text(
            widget.habit.title,
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              fontSize: 22,
            ),
          ),
          centerTitle: true,
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                icon: Icon(Icons.edit_rounded, color: Colors.indigo.shade600),
                onPressed: _showEditHabitDialog,
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildMilestoneTracker(),
                const SizedBox(height: 20),

                _buildTodayProgress(),
                const SizedBox(height: 24),

                Container(
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
                  ),
                  padding: const EdgeInsets.all(28),
                  child: widget.habit.type == HabitType.duration
                      ? _buildDurationUI()
                      : _buildCountQuantityUI(),
                ),
                const SizedBox(height: 32),

                const Text(
                  "Performance Metrics",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: Colors.black87,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 16),
                _buildStatsSection(),

                const SizedBox(height: 32),

                const Text(
                  "Activity History",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: Colors.black87,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 16),
                _buildConsistencyTimeline(),
                const SizedBox(height: 32),// 🔥 NEW: Recent Logs Section (Edit / Undo logic)
                _buildRecentLogsSection(),
                const SizedBox(height: 32),

                // 🔥 NEW: Manage Linked Groups Button
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => _ManageGroupsSheet(habit: widget.habit),
                      );
                    },
                    icon: Icon(
                      Icons.groups_rounded,
                      color: Colors.indigo.shade600,
                    ),
                    label: Text(
                      "Manage Shared Groups",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: BorderSide(color: Colors.indigo.shade200, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 🔥 NEW: Mark as Completed / Archive Button
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: ElevatedButton.icon(
                    onPressed: _archiveHabit,
                    icon: Icon(
                      Icons.task_alt_rounded,
                      color: Colors.green.shade700,
                    ),
                    label: Text(
                      "Mark Habit as Completed",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade50,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: Colors.green.shade200,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 🔥 NEW: The Recent Logs UI
  Widget _buildRecentLogsSection() {
    return ValueListenableBuilder(
      valueListenable: Hive.box<Sessions>('sessions').listenable(),
      builder: (context, Box<Sessions> box, _) {
        // Get sessions for this habit, sorted newest first
        final List<MapEntry<dynamic, Sessions>> recentSessions = box.toMap().entries
            .where((entry) => entry.value.habitId == widget.habit.id)
            .toList()
            ..sort((a, b) => b.value.date.compareTo(a.value.date));

        if (recentSessions.isEmpty) return const SizedBox.shrink();

        // Show max 5 recent logs to prevent overwhelming UI
        final displaySessions = recentSessions.take(5).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Recent Logs",
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.black87, letterSpacing: -0.5),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: displaySessions.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
                itemBuilder: (context, index) {
                  final entry = displaySessions[index];
                  final session = entry.value;

                  String timeString = "${session.date.hour.toString().padLeft(2, '0')}:${session.date.minute.toString().padLeft(2, '0')}";
                  String dateString = "${session.date.day}/${session.date.month}";

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.indigo.shade50, shape: BoxShape.circle),
                      child: Icon(Icons.history_rounded, color: Colors.indigo.shade400, size: 18),
                    ),
                    title: Text(
                      "+${session.value.toStringAsFixed(session.value.truncateToDouble() == session.value ? 0 : 1)} ${widget.habit.unit}",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Text("$dateString at $timeString", style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("+${session.xpEarned} XP", style: TextStyle(color: Colors.amber.shade600,
                         fontWeight: FontWeight.w900, fontSize: 12)),
                         const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(Icons.edit_rounded, color: Colors.indigo.shade300, size: 20),
                          constraints: const BoxConstraints(), // Makes the button smaller
                          padding: const EdgeInsets.all(4),
                          onPressed: () => _editSessionLog(entry.key, session),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade300, size: 20),
                          onPressed: () => _deleteSessionLog(entry.key, session),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMilestoneTracker() {
    int currentStreak = widget.habit.streak;
    int nextTarget = _milestones.keys.firstWhere(
      (k) => k > currentStreak,
      orElse: () => currentStreak + 100,
    );
    int previousTarget = 0;

    for (var key in _milestones.keys) {
      if (key <= currentStreak) previousTarget = key;
    }
    if (currentStreak == 0) previousTarget = 0;

    int daysLeft = nextTarget - currentStreak;
    int reward = _milestones[nextTarget] ?? 5000;
    double progress =
        (currentStreak - previousTarget) / (nextTarget - previousTarget);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade400, Colors.deepOrange.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.3),
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
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.local_fire_department_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "$daysLeft Days to Milestone!",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Hit $nextTarget days in a row to claim",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 10,
                    backgroundColor: Colors.black.withValues(alpha: 0.15),
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.star_rounded,
                      color: Colors.amber.shade600,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "+$reward XP",
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTodayProgress() {
    double todayValue = _getTodayProgress();
    double progress = todayValue / widget.habit.dailyTarget;
    bool isComplete = progress >= 1;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isComplete
              ? [Colors.teal.shade500, Colors.teal.shade700]
              : [Colors.indigo.shade600, Colors.indigo.shade900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: (isComplete ? Colors.teal : Colors.indigo).withValues(
              alpha: 0.3,
            ),
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
            children: [
              const Text(
                "Today's Progress",
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "${todayValue.toStringAsFixed(todayValue.truncateToDouble() == todayValue ? 0 : 1)} / ${widget.habit.dailyTarget} ${widget.habit.unit}",
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              child: LinearProgressIndicator(
                value: progress.clamp(0, 1),
                minHeight: 12,
                backgroundColor: Colors.black.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(
                  isComplete ? Colors.white : Colors.greenAccent.shade400,
                ),
              ),
            ),
          ),
          if (isComplete) ...[
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
                SizedBox(width: 6),
                Text(
                  "Daily Target Reached!",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formattedTime() {
    int s = _elapsedSeconds;
    if (widget.habit.unit == "hours") {
      int h = s ~/ 3600;
      int m = (s % 3600) ~/ 60;
      int sec = s % 60;
      return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}";
    }
    if (widget.habit.unit == "minutes") {
      int m = s ~/ 60;
      int sec = s % 60;
      return "${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}";
    }
    return "${s.toString().padLeft(2, '0')}s";
  }

  Widget _buildDurationUI() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timer_rounded, size: 16, color: Colors.grey.shade400),
            const SizedBox(width: 6),
            Text(
              "FOCUS TIMER",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Colors.grey.shade400,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 32),
          decoration: BoxDecoration(
            color: widget.habit.isRunning
                ? Colors.indigo.shade50
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: widget.habit.isRunning
                  ? Colors.indigo.shade100
                  : Colors.transparent,
            ),
          ),
          child: Center(
            child: Text(
              _formattedTime(),
              style: TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.w900,
                fontFamily: 'Courier',
                color: widget.habit.isRunning
                    ? Colors.indigo.shade900
                    : Colors.black87,
                letterSpacing: -2.0,
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 64,
          child: ElevatedButton(
            onPressed: widget.habit.isRunning ? _stopTimer : _startTimer,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.habit.isRunning
                  ? Colors.red.shade500
                  : Colors.black87,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.habit.isRunning
                      ? Icons.stop_rounded
                      : Icons.play_arrow_rounded,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Text(
                  widget.habit.isRunning ? "Stop Session" : "Start Session",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCountQuantityUI() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.edit_note_rounded, size: 16, color: Colors.grey.shade400),
            const SizedBox(width: 6),
            Text("LOG PROGRESS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey.shade400, letterSpacing: 1.5)),
          ],
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.indigo.shade400, Colors.indigo.shade600]),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.indigo.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 6))],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    if (_currentValue > 0) {
                      setState(() {
                        _currentValue--;
                        _valueController.text = _currentValue.toStringAsFixed(
                          _currentValue.truncateToDouble() == _currentValue ? 0 : 1,
                        );
                      });
                    }
                  },
                  child: Container(
                    width: 64, height: 64, alignment: Alignment.center,
                    child: const Icon(Icons.remove_rounded, color: Colors.white, size: 36),
                  ),
                ),
              ),
            ),
            Column(
              children: [
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: _valueController,
                    focusNode: _valueFocus,
                    // 🔥 THE FIX: Prevent entering massive numbers that break UI/Math
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(7),
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: -1.5),
                    decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                    onChanged: (value) => setState(() => _currentValue = double.tryParse(value) ?? 0),
                  ),
                ),
                Text(
                  widget.habit.unit.toUpperCase(),
                  style: TextStyle(color: Colors.indigo.shade400, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                ),
              ],
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.indigo.shade400, Colors.indigo.shade600]),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.indigo.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 6))],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    setState(() {
                      _currentValue++;
                      _valueController.text = _currentValue.toStringAsFixed(
                        _currentValue.truncateToDouble() == _currentValue ? 0 : 1,
                      );
                    });
                  },
                  child: Container(
                    width: 64, height: 64, alignment: Alignment.center,
                    child: const Icon(Icons.add_rounded, color: Colors.white, size: 36),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          height: 64,
          child: ElevatedButton(
            onPressed: _currentValue == 0 ? null : _saveCountQuantity,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade200,
              disabledForegroundColor: Colors.grey.shade400,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline_rounded, size: 24),
                SizedBox(width: 10),
                Text("Save Progress", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsSection() {
    return Row(
      children: [
        Expanded(
          child: _buildMiniStatCard(
            Icons.local_fire_department_rounded,
            "Streak",
            "${widget.habit.streak}",
            Colors.orange,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildMiniStatCard(
            Icons.star_rounded,
            "Total XP",
            "${widget.habit.totalXP}",
            Colors.amber,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildMiniStatCard(
            Icons.flag_rounded,
            "Target",
            "${widget.habit.dailyTarget}",
            Colors.blue,
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStatCard(
    IconData icon,
    String title,
    String value,
    MaterialColor color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color.shade600, size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConsistencyTimeline() {
    final sessionBox = Hive.box<Sessions>('sessions');
    final sessions = sessionBox.values
        .where((s) => s.habitId == widget.habit.id)
        .toList();

    List<DateTime> days = [];
    for (int i = 20; i >= 0; i--) {
      days.add(DateTime.now().subtract(Duration(days: i)));
    }

    Map<String, int> dailyXP = {};
    for (var session in sessions) {
      final key =
          "${session.date.year}-${session.date.month}-${session.date.day}";
      dailyXP[key] = (dailyXP[key] ?? 0) + session.xpEarned;
    }

    final ScrollController scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
      }
    });

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.timeline_rounded,
                    size: 16,
                    color: Colors.indigo.shade600,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  "21-Day Consistency",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 90,
            child: ListView.builder(
              controller: scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: days.length,
              itemBuilder: (context, index) {
                final d = days[index];
                final key = "${d.year}-${d.month}-${d.day}";
                final xp = dailyXP[key] ?? 0;
                final isToday = index == days.length - 1;
                final bool completed = xp > 0;

                return Container(
                  width: 52,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    gradient: completed
                        ? LinearGradient(
                            colors: [
                              Colors.indigo.shade400,
                              Colors.indigo.shade600,
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          )
                        : null,
                    color: completed ? null : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(100),
                    border: isToday && !completed
                        ? Border.all(color: Colors.indigo.shade200, width: 2)
                        : null,
                    boxShadow: completed
                        ? [
                            BoxShadow(
                              color: Colors.indigo.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : [],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        ['M', 'T', 'W', 'T', 'F', 'S', 'S'][d.weekday - 1],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: completed
                              ? Colors.white70
                              : Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${d.day}",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: completed ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: completed ? Colors.white : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  

  void _showEditHabitDialog() {
    final titleController = TextEditingController(text: widget.habit.title);
    final targetController = TextEditingController(
      text: widget.habit.dailyTarget.toStringAsFixed(
        widget.habit.dailyTarget.truncateToDouble() == widget.habit.dailyTarget
            ? 0
            : 1,
      ),
    );
    final unitController = TextEditingController(text: widget.habit.unit);

    double currentPool = widget.habit.xpPerUnit * widget.habit.dailyTarget;
    int initialDifficulty = 1;
    if (currentPool <= 55) {
      initialDifficulty = 0;
    } else if (currentPool <= 105) {
      initialDifficulty = 1;
    } else {
      initialDifficulty = 2;
    }

    showDialog(
      context: context,
      builder: (_) {
        HabitType selectedType = widget.habit.type;
        int selectedDifficulty = initialDifficulty;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            bool hasChanges = false;
            double? parsedTarget = double.tryParse(targetController.text);

            if (titleController.text.trim() != widget.habit.title) {
              hasChanges = true;
            }
            if (selectedType != widget.habit.type) {
              hasChanges = true;
            }
            if (unitController.text.trim() != widget.habit.unit) {
              hasChanges = true;
            }
            if (parsedTarget != null &&
                parsedTarget != widget.habit.dailyTarget) {
              hasChanges = true;
            }
            if (selectedDifficulty != initialDifficulty) {
              hasChanges = true;
            }

            if (titleController.text.trim().isEmpty ||
                parsedTarget == null ||
                parsedTarget <= 0) {
              hasChanges = false;
            }

            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              insetPadding: const EdgeInsets.all(20),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: Text(
                        "Edit Habit",
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          color: Colors.black87,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              controller: titleController,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                              onChanged: (_) => setDialogState(() {}),
                              decoration: InputDecoration(
                                labelText: "Habit Name",
                                labelStyle: TextStyle(
                                  color: Colors.grey.shade500,
                                ),
                                prefixIcon: Icon(
                                  Icons.title_rounded,
                                  color: Colors.grey.shade400,
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            Text(
                              "Habit Type",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade500,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: HabitType.values.map((type) {
                                bool isSelected = selectedType == type;
                                IconData icon = type == HabitType.duration
                                    ? Icons.timer_rounded
                                    : (type == HabitType.count
                                          ? Icons.repeat_rounded
                                          : Icons.water_drop_rounded);
                                return Expanded(
                                  child: GestureDetector(
                                    onTap: () => setDialogState(
                                      () => selectedType = type,
                                    ),
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Colors.indigo.shade50
                                            : Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: isSelected
                                              ? Colors.indigo.shade300
                                              : Colors.grey.shade200,
                                          width: isSelected ? 1.5 : 1,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Icon(
                                            icon,
                                            color: isSelected
                                                ? Colors.indigo.shade600
                                                : Colors.grey.shade400,
                                            size: 20,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            type.name,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: isSelected
                                                  ? Colors.indigo.shade700
                                                  : Colors.grey.shade500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 20),

                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: targetController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    onChanged: (_) => setDialogState(() {}),
                                    decoration: InputDecoration(
                                      labelText: "Target",
                                      labelStyle: TextStyle(
                                        color: Colors.grey.shade500,
                                      ),
                                      prefixIcon: Icon(
                                        Icons.flag_rounded,
                                        color: Colors.grey.shade400,
                                      ),
                                      filled: true,
                                      fillColor: Colors.grey.shade50,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: unitController,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    onChanged: (_) => setDialogState(() {}),
                                    decoration: InputDecoration(
                                      labelText: "Unit",
                                      labelStyle: TextStyle(
                                        color: Colors.grey.shade500,
                                      ),
                                      prefixIcon: Icon(
                                        Icons.straighten_rounded,
                                        color: Colors.grey.shade400,
                                      ),
                                      filled: true,
                                      fillColor: Colors.grey.shade50,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            Text(
                              "Difficulty Level",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade500,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _buildEditDifficultyOption(
                                  0,
                                  "Easy",
                                  Icons.spa_rounded,
                                  Colors.green,
                                  selectedDifficulty,
                                  (val) => setDialogState(
                                    () => selectedDifficulty = val,
                                  ),
                                ),
                                _buildEditDifficultyOption(
                                  1,
                                  "Medium",
                                  Icons.whatshot_rounded,
                                  Colors.orange,
                                  selectedDifficulty,
                                  (val) => setDialogState(
                                    () => selectedDifficulty = val,
                                  ),
                                ),
                                _buildEditDifficultyOption(
                                  2,
                                  "Hard",
                                  Icons.local_fire_department_rounded,
                                  Colors.red,
                                  selectedDifficulty,
                                  (val) => setDialogState(
                                    () => selectedDifficulty = val,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              FocusScope.of(context).unfocus();
                              Navigator.pop(context);
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: Text(
                              "Cancel",
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black87,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey.shade200,
                              disabledForegroundColor: Colors.grey.shade400,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            onPressed: hasChanges
                                ? () async {
                                    FocusScope.of(context).unfocus();

                                    double newTarget = double.parse(
                                      targetController.text,
                                    ).clamp(1, 100000);

                                    double targetXpPool =
                                        selectedDifficulty == 0
                                        ? 50.0
                                        : (selectedDifficulty == 1
                                              ? 100.0
                                              : 150.0);
                                    double newXpPerUnit =
                                        targetXpPool / newTarget;

                                    widget.habit.title = titleController.text
                                        .trim();
                                    widget.habit.type = selectedType;
                                    widget.habit.unit = unitController.text
                                        .trim();
                                    widget.habit.dailyTarget = newTarget;
                                    widget.habit.xpPerUnit = newXpPerUnit;

                                    await widget.habit.save();

                                    _syncHabitEditToCloudInBackground();

                                    // ignore: use_build_context_synchronously
                                    Navigator.pop(context);
                                    setState(() {});
                                  }
                                : null,
                            child: const Text(
                              "Save",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEditDifficultyOption(
    int index,
    String label,
    IconData icon,
    MaterialColor color,
    int currentDiff,
    Function(int) onTap,
  ) {
    bool isSelected = currentDiff == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color.shade50 : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(14),
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
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? color.shade700 : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _syncHabitEditToCloudInBackground() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase
          .from('habits')
          .update({
            'title': widget.habit.title,
            'type': widget.habit.type.name,
            'daily_target': widget.habit.dailyTarget.toInt(),
          })
          .eq('id', widget.habit.id);

      debugPrint("✅ Habit edit synced to cloud.");
    } catch (e) {
      debugPrint("❌ Failed to sync habit edit: $e");
    }
  }

  void _showXpPopup(int xp) {
    _xpOverlay?.remove();
    _xpOverlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: MediaQuery.of(context).size.height * 0.15,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: AnimatedOpacity(
                  opacity: 1,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade600,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 16,
                          color: Colors.green.withValues(alpha: 0.4),
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "+$xp XP",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_xpOverlay!);
    Future.delayed(const Duration(seconds: 2), () {
      _xpOverlay?.remove();
      _xpOverlay = null;
    });
  }

  void _showMilestoneCelebration(int streak, int bonusXp) {
    _xpOverlay?.remove();
    _xpOverlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: MediaQuery.of(context).size.height * 0.15,
          left: 20,
          right: 20,
          child: IgnorePointer(
            child: Material(
              color: Colors.transparent,
              child: AnimatedOpacity(
                opacity: 1,
                duration: const Duration(milliseconds: 400),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.amber.shade400, Colors.orange.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 24,
                        color: Colors.orange.withValues(alpha: 0.5),
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.emoji_events_rounded,
                        color: Colors.white,
                        size: 56,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "$streak DAY STREAK!",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 26,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Milestone Reached",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "+$bonusXp BONUS XP",
                          style: TextStyle(
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_xpOverlay!);
    Future.delayed(const Duration(seconds: 4), () {
      _xpOverlay?.remove();
      _xpOverlay = null;
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _valueController.dispose();
    _valueFocus.dispose();
    super.dispose();
  }
}

// ==========================================
// 🔥 Manage Linked Groups Bottom Sheet
// ==========================================

class _ManageGroupsSheet extends StatefulWidget {
  final Habit habit;
  const _ManageGroupsSheet({required this.habit});

  @override
  State<_ManageGroupsSheet> createState() => _ManageGroupsSheetState();
}

class _ManageGroupsSheetState extends State<_ManageGroupsSheet> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _myGroups = [];
  late List<String> _selectedGroupIds;

  @override
  void initState() {
    super.initState();
    // Load the currently linked groups directly from the habit
    _selectedGroupIds = List.from(widget.habit.linkedGroupIds);
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

      final groups = <Map<String, dynamic>>[];
      for (var row in response) {
        if (row['groups'] != null) {
          groups.add({
            'id': row['group_id'],
            'name': row['groups']['name'],
          });
        }
      }

      if (mounted) {
        setState(() {
          _myGroups = groups;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Failed to fetch groups: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveLinks() async {
    setState(() => _isLoading = true);

    // 🔥 THE FIX: Force everything to Strings so Dart's .contains() works perfectly
    final oldLinks = widget.habit.linkedGroupIds.map((e) => e.toString()).toList();
    final newLinks = _selectedGroupIds.map((e) => e.toString()).toList();

    // Find exactly which groups were removed
    final unlinkedGroups = oldLinks.where((id) => !newLinks.contains(id)).toList();
    
    // 1. Update Local Hive Model
    widget.habit.linkedGroupIds = newLinks;
    await widget.habit.save();

    // 2. Update Cloud (Supabase)
    try {
      await Supabase.instance.client
          .from('habits')
          .update({'linked_group_ids': newLinks})
          .eq('id', widget.habit.id);

      // 3. Wipe the visual receipts!
      for (String groupId in unlinkedGroups) {
        debugPrint("Attempting to delete activity for Group: $groupId and Habit: ${widget.habit.id}");
        
        await Supabase.instance.client
            .from('group_activity')
            .delete()
            .eq('group_id', groupId)
            .eq('habit_id', widget.habit.id);
            
        debugPrint("✅ Successfully wiped activity feed for unlinked group.");
      }

    } catch (e) {
      debugPrint("❌ Failed to update cloud links or delete activity: $e");
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Group links updated for ${widget.habit.title}", style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.indigo.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
            const Text(
              "Share Progress",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Select which groups will see your XP and activity when you complete this habit.",
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.4),
            ),
            const SizedBox(height: 24),
            
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_myGroups.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    "You haven't joined any groups yet.",
                    style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold),
                  ),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _myGroups.map((group) {
                  final isSelected = _selectedGroupIds.contains(group['id']);
                  return FilterChip(
                    label: Text(
                      group['name'],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected ? Colors.indigo.shade700 : Colors.black87,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: Colors.indigo.shade50,
                    checkmarkColor: Colors.indigo.shade600,
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected ? Colors.indigo.shade300 : Colors.grey.shade300,
                        width: isSelected ? 1.5 : 1.0,
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
              
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveLinks,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: const Text("Save Links", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}