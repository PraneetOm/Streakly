import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/habit.dart';
import '../models/session.dart';
import 'dart:math';

enum AnalyticsRangeType { weekly, monthly, yearly, custom }

class AnalyticsScreen extends StatefulWidget {
  final AnalyticsRangeType selectedRange;
  final DateTime? customStart;
  final DateTime? customEnd;

  final void Function(AnalyticsRangeType range, DateTime? start, DateTime? end)
      onRangeChanged;

  const AnalyticsScreen({
    super.key,
    required this.selectedRange,
    required this.customStart,
    required this.customEnd,
    required this.onRangeChanged,
  });

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final Box<Habit> habitBox = Hive.box<Habit>('habits');
  final Box<Sessions> sessionBox = Hive.box<Sessions>('sessions');

  AnalyticsRangeType get _selectedRange => widget.selectedRange;
  
  bool _showArchivedInTop = false;
  
  String? _selectedHabitId;

  List<Sessions> _periodSessions(List<Sessions> all, DateTime from, DateTime to) {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day, 23, 59, 59);
    return all.where((s) => !s.date.isBefore(start) && !s.date.isAfter(end)).toList();
  }

  List<DateTime> _lastNDays(int n) {
    final now = DateTime.now();
    return List.generate(
      n,
      (i) => DateTime(now.year, now.month, now.day).subtract(Duration(days: n - 1 - i)),
    );
  }

  int _computeLongestStreakFromSessions(List<Sessions> sessions) {
    if (sessions.isEmpty) return 0;
    final days = sessions
        .map((s) => DateTime(s.date.year, s.date.month, s.date.day))
        .toSet()
        .toList()
      ..sort();

    int maxStreak = 0, cur = 1;
    for (int i = 1; i < days.length; i++) {
      final diff = days[i].difference(days[i - 1]).inDays;
      if (diff == 1) {
        cur++;
      } else if (diff > 1) {
        maxStreak = max(maxStreak, cur);
        cur = 1;
      }
    }
    return max(maxStreak, cur);
  }

  // 🔥 THE FIX: Now accepts a nullable habit so it can show ALL history!
  void _showHistorySheet(List<Sessions> habitSessions, {Habit? habit}) {
    final sortedSessions = List<Sessions>.from(habitSessions)
      ..sort((a, b) => b.date.compareTo(a.date));

    // We need all habits to look up names if viewing the "All Habits" history
    final allHabits = Hive.box<Habit>('habits').values.toList();
    final habitMap = {for (var h in allHabits) h.id: h};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Color(0xFFF4F6F9),
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 16, bottom: 24),
                width: 48,
                height: 6,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.indigo.shade50, shape: BoxShape.circle),
                      child: Icon(Icons.history_rounded, color: Colors.indigo.shade600),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Session History", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.black87)),
                          const SizedBox(height: 4),
                          Text(habit?.title ?? "All Habits", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: sortedSessions.isEmpty
                    ? Center(
                        child: Text("No logs found.", style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.only(left: 20, right: 20, bottom: 40),
                        itemCount: sortedSessions.length,
                        itemBuilder: (context, index) {
                          final session = sortedSessions[index];
                          final sessionHabit = habitMap[session.habitId];
                          
                          String timeString = "${session.date.hour.toString().padLeft(2, '0')}:${session.date.minute.toString().padLeft(2, '0')}";
                          String dateString = "${session.date.day}/${session.date.month}/${session.date.year}";

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey.shade100),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 4))],
                            ),
                            child: Row(
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(dateString, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black87)),
                                    const SizedBox(height: 4),
                                    Text(timeString, style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 12)),
                                  ],
                                ),
                                const Spacer(),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text("+${session.xpEarned} XP", style: TextStyle(color: Colors.amber.shade600, fontWeight: FontWeight.w900, fontSize: 16)),
                                    const SizedBox(height: 4),
                                    // 🔥 Show Habit Name if 'All Habits', else just the unit
                                    Text(
                                      habit == null 
                                        ? "${session.value.toStringAsFixed(session.value.truncateToDouble() == session.value ? 0 : 1)} ${sessionHabit?.unit ?? ''} • ${sessionHabit?.title ?? 'Unknown'}"
                                        : "${session.value.toStringAsFixed(session.value.truncateToDouble() == session.value ? 0 : 1)} ${sessionHabit?.unit ?? ''}", 
                                      style: TextStyle(color: Colors.indigo.shade400, fontWeight: FontWeight.bold, fontSize: 12)
                                    ),
                                  ],
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: ValueListenableBuilder(
        valueListenable: sessionBox.listenable(),
        builder: (context, _, _) {
          return ValueListenableBuilder(
            valueListenable: habitBox.listenable(),
            builder: (context, _, _) {
              final allSessions = sessionBox.values.toList();
              final habits = habitBox.values.toList();
              final now = DateTime.now();

              final targetSessions = _selectedHabitId == null 
                  ? allSessions 
                  : allSessions.where((s) => s.habitId == _selectedHabitId).toList();

              DateTime rangeStart;
              DateTime rangeEnd = now;
              int heatmapDays;

              switch (_selectedRange) {
                case AnalyticsRangeType.weekly:
                  rangeStart = now.subtract(const Duration(days: 6));
                  heatmapDays = 7;
                  break;
                case AnalyticsRangeType.monthly:
                  rangeStart = now.subtract(const Duration(days: 29));
                  heatmapDays = 30;
                  break;
                case AnalyticsRangeType.yearly:
                  rangeStart = now.subtract(const Duration(days: 364));
                  heatmapDays = 365;
                  break;
                case AnalyticsRangeType.custom:
                  rangeStart = widget.customStart ?? now.subtract(const Duration(days: 30));
                  rangeEnd = widget.customEnd ?? now;
                  
                  // 🔥 THE FIX: Strip time to ensure same-day selections always equal 1 day!
                  final d1 = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
                  final d2 = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
                  heatmapDays = d2.difference(d1).inDays + 1;
                  break;
              }

              final filteredSessions = _periodSessions(targetSessions, rangeStart, rangeEnd);
              
              final habitMap = {for (var h in habits) h.id: h};
              double totalMinutes = 0;
              for (final s in filteredSessions) {
                final habit = habitMap[s.habitId];
                if (habit != null && habit.type == HabitType.duration) {
                  if (habit.unit == 'seconds') {
                    totalMinutes += (s.value / 60);
                  } else if (habit.unit == 'hours') {
                    totalMinutes += (s.value * 60);
                  } else {
                    totalMinutes += s.value;
                  }
                }
              }

              final totalXP = filteredSessions.fold<int>(0, (sum, s) => sum + s.xpEarned);
              
              int longestStreakAll = 0;
              if (_selectedHabitId == null) {
                longestStreakAll = habits.isEmpty ? 0 : habits.map((h) => h.streak).reduce(max);
              } else {
                longestStreakAll = _computeLongestStreakFromSessions(targetSessions);
              }

              final last7 = _periodSessions(targetSessions, now.subtract(const Duration(days: 6)), now);
              final prev7 = _periodSessions(targetSessions, now.subtract(const Duration(days: 13)), now.subtract(const Duration(days: 7)));

              final xpLast7 = last7.fold<int>(0, (sum, s) => sum + s.xpEarned);
              final xpPrev7 = prev7.fold<int>(0, (sum, s) => sum + s.xpEarned);

              double weeklyGrowth = xpPrev7 > 0 ? ((xpLast7 - xpPrev7) / xpPrev7) * 100 : 0;
              bool burnout = xpPrev7 > 0 && xpLast7 < (xpPrev7 * 0.5);

              String momentum = 'Stable Progress';
              Color momentumColor = Colors.blue.shade600;
              IconData momentumIcon = Icons.trending_flat_rounded;

              if (xpPrev7 > 0) {
                if (weeklyGrowth >= 15) {
                  momentum = 'Gaining Momentum!';
                  momentumColor = Colors.green.shade600;
                  momentumIcon = Icons.trending_up_rounded;
                } else if (weeklyGrowth <= -15) {
                  momentum = 'Slight Decline';
                  momentumColor = Colors.orange.shade600;
                  momentumIcon = Icons.trending_down_rounded;
                }
              } else if (xpLast7 > 0) {
                momentum = 'Gaining Momentum!';
                momentumColor = Colors.green.shade600;
                momentumIcon = Icons.trending_up_rounded;
              }

              List<DateTime> heatmapDates = _selectedRange == AnalyticsRangeType.custom
                  ? List.generate(heatmapDays, (i) => DateTime(rangeStart.year, rangeStart.month, rangeStart.day).add(Duration(days: i)))
                  : _lastNDays(heatmapDays);

              final heatmapMap = <DateTime, int>{};
              for (final s in filteredSessions) {
                final d = DateTime(s.date.year, s.date.month, s.date.day);
                heatmapMap[d] = (heatmapMap[d] ?? 0) + s.xpEarned;
              }

              final weekdayMap = {for (var i = 1; i <= 7; i++) i: 0};
              final timeBuckets = {
                'Morning (5AM-12PM)': 0,
                'Afternoon (12PM-5PM)': 0,
                'Evening (5PM-9PM)': 0,
                'Night Owl (9PM-5AM)': 0,
              };

              for (final s in targetSessions) {
                weekdayMap[s.date.weekday] = weekdayMap[s.date.weekday]! + s.xpEarned;
                final h = s.date.hour;
                if (h >= 5 && h < 12) {
                  timeBuckets['Morning (5AM-12PM)'] = timeBuckets['Morning (5AM-12PM)']! + s.xpEarned;
                } else if (h >= 12 && h < 17) {
                  timeBuckets['Afternoon (12PM-5PM)'] = timeBuckets['Afternoon (12PM-5PM)']! + s.xpEarned;
                } else if (h >= 17 && h < 21) {
                  timeBuckets['Evening (5PM-9PM)'] = timeBuckets['Evening (5PM-9PM)']! + s.xpEarned;
                } else {
                  timeBuckets['Night Owl (9PM-5AM)'] = timeBuckets['Night Owl (9PM-5AM)']! + s.xpEarned;
                }
              }

              int bestWeekday = weekdayMap.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
              String primeTime = timeBuckets.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
              final weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

              final habitStats = habits
                  .where((h) => _showArchivedInTop ? true : !h.isArchived)
                  .map((h) {
                final s = allSessions.where((ss) => ss.habitId == h.id).toList();
                return {
                  'habit': h,
                  'totalSessions': s.length,
                  'totalXP': s.fold<int>(0, (sum, e) => sum + e.xpEarned),
                  'longestStreak': _computeLongestStreakFromSessions(s),
                };
              }).toList()
                ..sort((a, b) => (b['totalXP'] as int).compareTo(a['totalXP'] as int));

              return SafeArea(
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "Analytics",
                                  style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.black87,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                _buildHabitSelector(habits),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildSegmentedControl(),
                          ],
                        ),
                      ),
                    ),

                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _KpiCard(
                                    title: 'Total XP',
                                    value: '$totalXP',
                                    icon: Icons.star_rounded,
                                    colors: [Colors.orange.shade700, Colors.deepOrange.shade900],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _KpiCard(
                                    title: 'Focus Minutes',
                                    value: totalMinutes.toStringAsFixed(0),
                                    icon: Icons.timer_rounded,
                                    colors: [Colors.indigo.shade700, Colors.indigo.shade900],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _KpiCard(
                                    title: 'Best Streak',
                                    value: '$longestStreakAll Days',
                                    icon: Icons.local_fire_department_rounded,
                                    colors: [Colors.red.shade700, Colors.red.shade900],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _KpiCard(
                                    title: '7-Day Growth',
                                    value: '${weeklyGrowth > 0 ? '+' : ''}${weeklyGrowth.toStringAsFixed(1)}%',
                                    icon: weeklyGrowth >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                                    colors: weeklyGrowth >= 0 
                                      ? [Colors.teal.shade700, Colors.teal.shade900] 
                                      : [Colors.red.shade700, Colors.red.shade900],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        child: _HeatmapWidget(
                          data: heatmapMap,
                          dates: heatmapDates,
                          onTapDay: (date, xp) {},
                        ),
                      ),
                    ),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Behavioral Patterns',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87),
                            ),
                            const SizedBox(height: 16),
                            
                            _buildInsightCard(
                              icon: momentumIcon, 
                              color: momentumColor, 
                              title: 'Current Momentum', 
                              highlight: momentum,
                              subtitle: 'Based on your last 7 days of XP.'
                            ),
                            
                            _buildInsightCard(
                              icon: Icons.event_available_rounded, 
                              color: Colors.purple.shade600, 
                              title: 'Most Productive Day', 
                              highlight: '${weekdayNames[bestWeekday - 1]}s',
                              subtitle: 'You consistently earn the most XP on this day.'
                            ),

                            _buildInsightCard(
                              icon: Icons.schedule_rounded, 
                              color: Colors.blue.shade600, 
                              title: 'Your Prime Time', 
                              highlight: primeTime,
                              subtitle: 'You build the most habits during this block.'
                            ),

                            if (burnout)
                              _buildInsightCard(
                                icon: Icons.warning_amber_rounded, 
                                color: Colors.red.shade600, 
                                title: 'Burnout Warning', 
                                highlight: 'Activity Dropped',
                                subtitle: 'Your XP dropped significantly this week. Rest is important!'
                              ),
                          ],
                        ),
                      ),
                    ),

                    // 🔥 TOP PERFORMING HABITS (Only visible globally)
                    if (_selectedHabitId == null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Top Performing Habits',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        "Include Completed", 
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.grey.shade600)
                                      ),
                                      const SizedBox(width: 12),
                                      SizedBox(
                                        height: 24,
                                        width: 40,
                                        child: Switch(
                                          value: _showArchivedInTop,
                                          onChanged: (val) => setState(() => _showArchivedInTop = val),
                                          activeColor: Colors.indigo,
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              if (habitStats.isEmpty)
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(40.0),
                                    child: Column(
                                      children: [
                                        Icon(Icons.query_stats_rounded, size: 48, color: Colors.grey.shade300),
                                        const SizedBox(height: 12),
                                        Text("No data to rank yet.", style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                )
                              else
                                ...List.generate(
                                  habitStats.length > 5 ? 5 : habitStats.length,
                                  (index) {
                                    final stat = habitStats[index];
                                    final habit = stat['habit'] as Habit;
                                    final isTop = index == 0;

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: isTop ? Colors.amber.shade200 : Colors.grey.shade100, width: isTop ? 2 : 1),
                                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 4))],
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 40, height: 40,
                                            decoration: BoxDecoration(
                                              color: isTop ? Colors.amber.shade100 : Colors.grey.shade100,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Center(
                                              child: Text(
                                                '#${index + 1}',
                                                style: TextStyle(fontWeight: FontWeight.w900, color: isTop ? Colors.amber.shade800 : Colors.grey.shade600, fontSize: 16),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        habit.title,
                                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    if (habit.isArchived)
                                                      Container(
                                                        margin: const EdgeInsets.only(left: 8),
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: Colors.green.shade50, 
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(color: Colors.green.shade200)
                                                        ),
                                                        child: Text(
                                                          "COMPLETED", 
                                                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.green.shade700, letterSpacing: 0.5)
                                                        ),
                                                      )
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '${stat['totalXP']} XP  •  ${stat['longestStreak']} Day Peak Streak',
                                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    
                    // 🔥 THE FIX: Data Vault is ALWAYS visible now!
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Data Vault',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 64,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  if (_selectedHabitId == null) {
                                    _showHistorySheet(targetSessions); // Shows ALL habits history
                                  } else {
                                    final h = habitMap[_selectedHabitId];
                                    if (h != null) _showHistorySheet(targetSessions, habit: h);
                                  }
                                },
                                icon: Icon(Icons.history_rounded, color: Colors.indigo.shade700),
                                label: Text(
                                  "View Complete History",
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo.shade800),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigo.shade50,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    side: BorderSide(color: Colors.indigo.shade200, width: 2),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 100), // Ensures bottom spacing fits above nav bar
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildHabitSelector(List<Habit> habits) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _selectedHabitId,
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.indigo.shade600),
          isDense: true,
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(20),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text("All Habits", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.indigo.shade700)),
            ),
            ...habits.map((h) => DropdownMenuItem<String?>(
              value: h.id,
              child: SizedBox(
                width: 120, // Keep dropdown cleanly sized
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        h.title,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (h.isArchived)
                      Icon(Icons.check_circle_rounded, size: 12, color: Colors.green.shade500),
                  ],
                ),
              ),
            )),
          ],
          onChanged: (val) => setState(() => _selectedHabitId = val),
        ),
      ),
    );
  }

  Widget _buildInsightCard({required IconData icon, required Color color, required String title, required String highlight, required String subtitle}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.04), 
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.15), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [
              BoxShadow(color: color.withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 4))
            ]),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.grey.shade600)),
                const SizedBox(height: 2),
                Text(highlight, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: color, letterSpacing: -0.5)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedControl() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          _buildSegmentTab("Week", AnalyticsRangeType.weekly),
          _buildSegmentTab("Month", AnalyticsRangeType.monthly),
          _buildSegmentTab("Year", AnalyticsRangeType.yearly),
          _buildSegmentTab("Custom", AnalyticsRangeType.custom),
        ],
      ),
    );
  }

  Widget _buildSegmentTab(String title, AnalyticsRangeType type) {
    final isSelected = _selectedRange == type;
    return Expanded(
      child: GestureDetector(
        onTap: () async {
          if (type == AnalyticsRangeType.custom) {
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
              builder: (context, child) => Theme(
                data: ThemeData.light().copyWith(colorScheme: ColorScheme.light(primary: Colors.indigo.shade600)),
                child: child!,
              ),
            );
            if (picked != null) widget.onRangeChanged(type, picked.start, picked.end);
          } else {
            widget.onRangeChanged(type, null, null);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)] : [],
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isSelected ? Colors.indigo.shade700 : Colors.grey.shade600),
            ),
          ),
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final List<Color> colors;

  const _KpiCard({required this.title, required this.value, required this.icon, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: colors[0].withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.85)),
          ),
        ],
      ),
    );
  }
}

class _HeatmapWidget extends StatefulWidget {
  final Map<DateTime, int> data;
  final List<DateTime> dates;
  final void Function(DateTime date, int xp) onTapDay;

  const _HeatmapWidget({required this.data, required this.dates, required this.onTapDay});

  @override
  State<_HeatmapWidget> createState() => _HeatmapWidgetState();
}

class _HeatmapWidgetState extends State<_HeatmapWidget> {
  final ScrollController _scrollController = ScrollController();

  void _scrollToEnd() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  @override
  void didUpdateWidget(covariant _HeatmapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  Color _colorForValue(int xp) {
    if (xp == 0) return Colors.grey.shade100;
    if (xp <= 20) return Colors.indigo.shade200;
    if (xp <= 50) return Colors.indigo.shade300;
    if (xp <= 100) return Colors.indigo.shade500;
    return Colors.indigo.shade700; 
  }

  @override
  Widget build(BuildContext context) {
    List<List<DateTime?>> weeks = [];
    if (widget.dates.isEmpty) return const SizedBox();

    DateTime start = widget.dates.first;
    int startWeekday = start.weekday;
    List<DateTime?> currentWeek = List.filled(startWeekday - 1, null, growable: true);

    for (final date in widget.dates) {
      if (currentWeek.length == 7) {
        weeks.add(List.from(currentWeek));
        currentWeek = [];
      }
      currentWeek.add(date);
    }
    while (currentWeek.length < 7) {
      currentWeek.add(null);
    }
    weeks.add(currentWeek);

    double cellSize = 16;
    double spacing = 4;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.grid_view_rounded, size: 18, color: Colors.indigo.shade400),
              const SizedBox(width: 8),
              const Text("Activity Heatmap", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black87)),
            ],
          ),
          const SizedBox(height: 20),
          SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: SizedBox(
              height: (cellSize * 7) + (spacing * 6),
              child: Row(
                children: weeks.map((week) {
                  return Padding(
                    padding: EdgeInsets.only(right: spacing),
                    child: Column(
                      children: week.map((date) {
                        if (date == null) {
                          return SizedBox(width: cellSize, height: cellSize + (date == week.last ? 0 : spacing));
                        }
                        int xp = widget.data[date] ?? 0;
                        return Container(
                          width: cellSize,
                          height: cellSize,
                          margin: EdgeInsets.only(bottom: date == week.last ? 0 : spacing),
                          decoration: BoxDecoration(
                            color: _colorForValue(xp),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }).toList(),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Less', style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              _LegendBox(color: Colors.grey.shade100),
              const SizedBox(width: 4),
              _LegendBox(color: Colors.indigo.shade200),
              const SizedBox(width: 4),
              _LegendBox(color: Colors.indigo.shade300),
              const SizedBox(width: 4),
              _LegendBox(color: Colors.indigo.shade500),
              const SizedBox(width: 4),
              _LegendBox(color: Colors.indigo.shade700),
              const SizedBox(width: 6),
              Text('More', style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendBox extends StatelessWidget {
  final Color color;
  const _LegendBox({required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)));
  }
}