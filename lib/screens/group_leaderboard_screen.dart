import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GroupLeaderboardScreen extends StatefulWidget {
  final dynamic groupId;
  final String groupName;

  const GroupLeaderboardScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupLeaderboardScreen> createState() => _GroupLeaderboardScreenState();
}

class _GroupLeaderboardScreenState extends State<GroupLeaderboardScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];
  String _currentInterval = 'weekly';

  String? get _myUserId => _supabase.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  DateTime _getPeriodStartDate(String interval) {
    final now = DateTime.now().toLocal();

    switch (interval) {
      case 'daily':
        return DateTime(now.year, now.month, now.day);
      case 'weekly':
        int daysToSubtract = now.weekday - 1;
        return DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: daysToSubtract));
      case 'monthly':
        return DateTime(now.year, now.month, 1);
      case 'yearly':
        return DateTime(now.year, 1, 1);
      default:
        int fallbackSubtract = now.weekday - 1;
        return DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: fallbackSubtract));
    }
  }

  Future<void> _loadLeaderboard() async {
    setState(() => _loading = true);
    final supabase = Supabase.instance.client;

    try {
      final groupData = await supabase
          .from('groups')
          .select('reset_interval')
          .eq('id', widget.groupId)
          .maybeSingle();

      _currentInterval = groupData?['reset_interval']?.toString() ?? 'weekly';
      final startDate = _getPeriodStartDate(_currentInterval);

      final membersResp = await supabase
          .from('group_members')
          .select('user_id, status')
          .eq('group_id', widget.groupId)
          .eq('status', 'active');

      // 🔥 THE MASTER FIX: Query habit_sessions with an INNER JOIN to habits.
      // This forces the database to ONLY return sessions if the parent habit 
      // is CURRENTLY linked to this group! If unlinked, the XP vanishes instantly.
      final sessionsResp = await supabase
          .from('habit_sessions')
          .select('user_id, flow_points, habits!inner(linked_group_ids)')
          .contains('habits.linked_group_ids', [widget.groupId])
          .gte('started_at', startDate.toUtc().toIso8601String());

      final sessions = (sessionsResp as List).cast<Map<String, dynamic>>();

      Map<String, int> scores = {};
      for (var session in sessions) {
        String? uid = session['user_id']?.toString();
        if (uid == null) continue;

        int xp = (session['flow_points'] as num?)?.toInt() ?? 0;
        scores[uid] = (scores[uid] ?? 0) + xp;
      }

      List<Map<String, dynamic>> ranks = [];
      for (var member in membersResp) {
        String? uid = member['user_id']?.toString();
        if (uid == null) continue;

        String name = 'Unknown User';
        final profile = await supabase
            .from('profiles')
            .select('full_name')
            .eq('id', uid)
            .maybeSingle();

        if (profile != null && profile['full_name'] != null) {
          name = profile['full_name'].toString();
        }

        ranks.add({
          'user_id': uid,
          'display_name': name,
          'total_xp': scores[uid] ?? 0,
        });
      }

      ranks.sort(
        (a, b) => (b['total_xp'] as int).compareTo(a['total_xp'] as int),
      );

      setState(() {
        _rows = ranks;
      });
    } catch (e) {
      debugPrint("Leaderboard error: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMemberProfile(
    String userId,
    String userName,
    int rank,
    int totalXp,
  ) {
    if (_myUserId == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MemberProfileSheet(
        targetUserId: userId,
        targetUserName: userName,
        rank: rank,
        totalXp: totalXp,
        groupId: widget.groupId,
        currentUserId: _myUserId!,
        currentInterval: _currentInterval, 
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildAppBar(),
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_rows.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.group_off_rounded,
                      size: 48,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No members yet.',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            SliverToBoxAdapter(child: _buildPodiumSection()),
            _buildLeaderboardList(),
          ],
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 130.0,
      floating: false,
      pinned: true,
      backgroundColor: Colors.indigo.shade600,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 48, bottom: 16),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.groupName} Rankings',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _currentInterval.toUpperCase(),
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.indigo.shade900, Colors.indigo.shade500],
            ),
          ),
        ),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _loadLeaderboard,
          ),
        ),
      ],
    );
  }

  Widget _buildPodiumSection() {
    final first = _rows.isNotEmpty ? _rows[0] : null;
    final second = _rows.length > 1 ? _rows[1] : null;
    final third = _rows.length > 2 ? _rows[2] : null;

    return Container(
      padding: const EdgeInsets.only(top: 30, bottom: 20, left: 16, right: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (second != null) Expanded(child: _podiumItem(second, 2, 100)),
          if (first != null) Expanded(child: _podiumItem(first, 1, 140)),
          if (third != null) Expanded(child: _podiumItem(third, 3, 80)),
        ],
      ),
    );
  }

  Widget _podiumItem(Map<String, dynamic> user, int rank, double height) {
    final isMe = user['user_id'] == _myUserId;
    final xp = user['total_xp'] ?? 0;
    final rawName = user['display_name']?.toString() ?? "User";
    final displayName = isMe ? "You" : rawName.split(' ').first;
    final initial = rawName.isNotEmpty ? rawName[0].toUpperCase() : '?';

    List<Color> gradientColors;
    Color borderColor;
    if (rank == 1) {
      gradientColors = [Colors.amber.shade300, Colors.orange.shade500];
      borderColor = Colors.amber.shade400;
    } else if (rank == 2) {
      gradientColors = [Colors.grey.shade300, Colors.grey.shade500];
      borderColor = Colors.grey.shade400;
    } else {
      gradientColors = [Colors.orange.shade300, Colors.deepOrange.shade400];
      borderColor = Colors.deepOrange.shade300;
    }

    return GestureDetector(
      onTap: () => _showMemberProfile(user['user_id'], rawName, rank, xp),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Stack(
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: borderColor,
                    width: rank == 1 ? 4 : 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: borderColor.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: rank == 1 ? 36 : 28,
                  backgroundColor: Colors.white,
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: borderColor,
                      fontWeight: FontWeight.w900,
                      fontSize: rank == 1 ? 28 : 22,
                    ),
                  ),
                ),
              ),
              if (rank == 1)
                const Positioned(
                  top: -22,
                  child: Text(
                    "👑",
                    style: TextStyle(
                      fontSize: 32,
                      shadows: [
                        Shadow(
                          color: Colors.black26,
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 80,
            child: Text(
              displayName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isMe ? FontWeight.w900 : FontWeight.w700,
                fontSize: 14,
                color: isMe ? Colors.indigo.shade700 : Colors.black87,
              ),
            ),
          ),
          Text(
            '$xp XP',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.indigo.shade300,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 800),
            curve: Curves.elasticOut,
            height: height,
            width: 70,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(
                  color: gradientColors.last.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                '$rank',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardList() {
    final listItems = _rows.length > 3 ? _rows.sublist(3) : [];

    if (listItems.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox(height: 40));
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final row = listItems[index];
          final userId = row['user_id'].toString();
          final xp = row['total_xp'] ?? 0;
          final isMe = userId == _myUserId;
          final rawName = (row['display_name'] ?? 'User').toString();
          final name = isMe ? "You" : rawName;
          final initial = rawName.isNotEmpty ? rawName[0].toUpperCase() : '?';
          final rank = index + 4;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: isMe ? Colors.indigo.shade50 : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: isMe
                  ? Border.all(color: Colors.indigo.shade200, width: 2)
                  : Border.all(color: Colors.grey.shade100),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _showMemberProfile(userId, rawName, rank, xp),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 32,
                        child: Text(
                          '#$rank',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Colors.grey.shade400,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: isMe
                            ? Colors.indigo.shade600
                            : Colors.grey.shade100,
                        child: Text(
                          initial,
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.grey.shade600,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontWeight: isMe
                                ? FontWeight.w900
                                : FontWeight.w700,
                            fontSize: 16,
                            color: isMe
                                ? Colors.indigo.shade900
                                : Colors.black87,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Colors.indigo.shade100
                              : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$xp XP',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: isMe
                                ? Colors.indigo.shade700
                                : Colors.green.shade700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }, childCount: listItems.length),
      ),
    );
  }
}

// ==========================================
// 🔥 Next-Gen Member Profile & Accountability
// ==========================================

class _MemberProfileSheet extends StatefulWidget {
  final String targetUserId;
  final String targetUserName;
  final int rank;
  final int totalXp;
  final dynamic groupId;
  final String currentUserId;
  final String currentInterval; 

  const _MemberProfileSheet({
    required this.targetUserId,
    required this.targetUserName,
    required this.rank,
    required this.totalXp,
    required this.groupId,
    required this.currentUserId,
    required this.currentInterval,
  });

  @override
  State<_MemberProfileSheet> createState() => _MemberProfileSheetState();
}

class _MemberProfileSheetState extends State<_MemberProfileSheet> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _sharedHabits = [];

  bool _nudgeSent = false;
  bool _highFiveSent = false;
  bool _showLifetime = false;

  @override
  void initState() {
    super.initState();
    _fetchSharedHabits();
  }

  DateTime _getPeriodStartDate() {
    final now = DateTime.now().toLocal();
    switch (widget.currentInterval) {
      case 'daily':
        return DateTime(now.year, now.month, now.day);
      case 'weekly':
        return DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
      case 'monthly':
        return DateTime(now.year, now.month, 1);
      case 'yearly':
        return DateTime(now.year, 1, 1);
      default:
        return DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
    }
  }

  String get _intervalLabel {
    if (widget.currentInterval == 'daily') return 'Today';
    if (widget.currentInterval == 'weekly') return 'This Week';
    if (widget.currentInterval == 'monthly') return 'This Month';
    if (widget.currentInterval == 'yearly') return 'This Year';
    return 'Current Period';
  }

  double _asDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  String _formatHabitValue(double value, String type, String unit) {
    if (value <= 0) return '0 $unit';

    if (type == 'duration') {
      String lUnit = unit.toLowerCase();
      if (lUnit == 'minutes' || lUnit == 'min') {
        int totalSeconds = (value * 60).round();
        if (totalSeconds < 60) return '$totalSeconds sec';
        int m = totalSeconds ~/ 60;
        int s = totalSeconds % 60;
        if (s == 0) return '$m min';
        return '$m min $s sec';
      } 
      else if (lUnit == 'hours' || lUnit == 'hr') {
        int totalMinutes = (value * 60).round();
        if (totalMinutes < 60) return '$totalMinutes min';
        int h = totalMinutes ~/ 60;
        int m = totalMinutes % 60;
        if (m == 0) return '$h hr';
        return '$h hr $m min';
      } 
      else if (lUnit == 'seconds' || lUnit == 'sec') {
        return '${value.toInt()} sec';
      }
    }

    if (value % 1 == 0) return '${value.toInt()} $unit';
    return '${value.toStringAsFixed(1)} $unit';
  }

  Widget _buildStatPill({
    required IconData icon,
    required String text,
    required Color background,
    required Color foreground,
    Color? borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor ?? background, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchSharedHabits() async {
    try {
      final supabase = Supabase.instance.client;

      final habitsResp = await supabase
          .from('habits')
          .select('*, streaks(current_streak)')
          .eq('user_id', widget.targetUserId)
          .contains('linked_group_ids', [widget.groupId]);

      final sessionsResp = await supabase
          .from('habit_sessions')
          .select('habit_id, value, flow_points, started_at')
          .eq('user_id', widget.targetUserId)
          .order('started_at', ascending: false);

      final sessionsByHabit = <String, List<Map<String, dynamic>>>{};
      for (final item in List<Map<String, dynamic>>.from(sessionsResp)) {
        final habitId = item['habit_id']?.toString();
        if (habitId == null) continue;
        sessionsByHabit.putIfAbsent(habitId, () => []).add(item);
      }

      final startDate = _getPeriodStartDate();

      if (!mounted) return;
      setState(() {
        _sharedHabits = List<Map<String, dynamic>>.from(habitsResp).map((
          habit,
        ) {
          int streakValue = 0;
          if (habit['streaks'] != null) {
            if (habit['streaks'] is List && habit['streaks'].isNotEmpty) {
              streakValue = _asInt(habit['streaks'][0]['current_streak']);
            } else if (habit['streaks'] is Map) {
              streakValue = _asInt(habit['streaks']['current_streak']);
            }
          }
          habit['streak'] = streakValue;

          double lifetimeValue = 0;
          double intervalValue = 0;
          int lifetimeXp = 0;
          int intervalXp = 0;

          final habitSessions = sessionsByHabit[habit['id'].toString()] ?? [];

          for (final session in habitSessions) {
            final rawValue = session['value'] ?? session['flow_points'] ?? 0;
            final activityValue = _asDouble(rawValue);
            final xp = _asInt(session['flow_points']);

            lifetimeValue += activityValue;
            lifetimeXp += xp;

            final startedAt = session['started_at'];
            if (startedAt != null) {
              final sessionDate = DateTime.parse(
                startedAt.toString(),
              ).toLocal();
              if (!sessionDate.isBefore(startDate)) {
                intervalValue += activityValue;
                intervalXp += xp;
              }
            }
          }

          habit['lifetime_value'] = lifetimeValue;
          habit['interval_value'] = intervalValue;
          habit['lifetime_xp'] = lifetimeXp;
          habit['interval_xp'] = intervalXp;
          habit['session_count'] = habitSessions.length;

          return habit;
        }).toList();

        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Failed to fetch shared habits: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendInteraction(String type) async {
    if (type == 'nudge' && _nudgeSent) return;
    if (type == 'high_five' && _highFiveSent) return;

    setState(() {
      if (type == 'nudge') _nudgeSent = true;
      if (type == 'high_five') _highFiveSent = true;
    });

    try {
      final supabase = Supabase.instance.client;
      final profile = await supabase
          .from('profiles')
          .select('full_name')
          .eq('id', widget.currentUserId)
          .maybeSingle();
      final myName = profile?['full_name'] ?? 'A group member';

      String title = type == 'nudge' ? '🔔 Gentle Nudge' : '✋ High Five!';
      String body = type == 'nudge'
          ? '$myName nudged ${widget.targetUserName} to keep their habits going!'
          : '$myName sent a high-five to ${widget.targetUserName} for their awesome progress!';

      await supabase.from('group_activity').insert({
        'group_id': widget.groupId,
        'user_id': widget.targetUserId,
        'actor_user_id': widget.currentUserId,
        'actor_name': myName,
        'xp': 0,
        'activity_type': type,
        'title': title,
        'body': body,
      });
    } catch (e) {
      debugPrint("Failed to send interaction: $e");
    }

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          if (type == 'nudge') _nudgeSent = false;
          if (type == 'high_five') _highFiveSent = false;
        });
      }
    });
  }

  IconData _getIconForType(String type) {
    if (type == 'duration') return Icons.timer_rounded;
    if (type == 'quantity') return Icons.water_drop_rounded;
    return Icons.repeat_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.targetUserName.isNotEmpty
        ? widget.targetUserName[0].toUpperCase()
        : '?';
    final isMe = widget.targetUserId == widget.currentUserId;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFFF4F6F9),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 20),
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.indigo.withValues(alpha: 0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.indigo.shade600,
                    child: Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
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
                        isMe
                            ? "${widget.targetUserName} (You)"
                            : widget.targetUserName,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Colors.black87,
                          letterSpacing: -0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildStatBadge(
                            Icons.leaderboard_rounded,
                            "Rank #${widget.rank}",
                            Colors.amber,
                          ),
                          const SizedBox(width: 8),
                          _buildStatBadge(
                            Icons.star_rounded,
                            "${widget.totalXp} XP",
                            Colors.green,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (!isMe)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _sendInteraction('nudge'),
                      icon: Text(
                        _nudgeSent ? "✅" : "🔔",
                        style: const TextStyle(fontSize: 16),
                      ),
                      label: Text(
                        _nudgeSent ? "Sent!" : "Nudge",
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _nudgeSent
                            ? Colors.orange.shade600
                            : Colors.white,
                        foregroundColor: _nudgeSent
                            ? Colors.white
                            : Colors.orange.shade700,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: _nudgeSent
                                ? Colors.transparent
                                : Colors.orange.shade200,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _sendInteraction('high_five'),
                      icon: Text(
                        _highFiveSent ? "✅" : "✋",
                        style: const TextStyle(fontSize: 16),
                      ),
                      label: Text(
                        _highFiveSent ? "Sent!" : "High Five",
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _highFiveSent
                            ? Colors.green.shade600
                            : Colors.white,
                        foregroundColor: _highFiveSent
                            ? Colors.white
                            : Colors.green.shade700,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: _highFiveSent
                                ? Colors.transparent
                                : Colors.green.shade200,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (!isMe) const SizedBox(height: 24),

          Container(
            height: 48,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(16),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth / 2;

                return Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      left: _showLifetime ? width : 0,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: width,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _showLifetime = false),
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              height: double.infinity,
                              child: _buildToggleText(
                                _intervalLabel,
                                !_showLifetime,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _showLifetime = true),
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              height: double.infinity,
                              child: _buildToggleText(
                                "Lifetime",
                                _showLifetime,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _sharedHabits.isEmpty
                    ? Center(
                        child: Text(
                          isMe
                              ? "You haven't shared any habits here."
                              : "No shared habits yet.",
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        physics: const BouncingScrollPhysics(),
                        itemCount: _sharedHabits.length,
                        itemBuilder: (context, index) {
                          final habit = _sharedHabits[index];
                          final isArchived = habit['isArchived'] == true;
                          final habitType = (habit['type'] ?? '').toString();
                          final habitUnit = (habit['unit'] ?? '').toString();

                          final displayedValue = _showLifetime
                              ? (habit['lifetime_value'] ?? 0).toDouble()
                              : (habit['interval_value'] ?? 0).toDouble();

                          final displayedXp = _showLifetime
                              ? _asInt(habit['lifetime_xp'])
                              : _asInt(habit['interval_xp']);

                          final activityLabel = _formatHabitValue(displayedValue, habitType, habitUnit);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: isArchived
                                          ? Colors.green.shade50
                                          : Colors.indigo.shade50,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Icon(
                                      isArchived
                                          ? Icons.check_rounded
                                          : _getIconForType(habitType),
                                      color: isArchived
                                          ? Colors.green.shade600
                                          : Colors.indigo.shade500,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          habit['title'] ?? 'Unknown',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                            color: isArchived
                                                ? Colors.grey.shade400
                                                : Colors.black87,
                                            decoration: isArchived
                                                ? TextDecoration.lineThrough
                                                : null,
                                            letterSpacing: -0.3,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 10),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            _buildStatPill(
                                              icon: Icons.fitness_center_rounded,
                                              text: activityLabel,
                                              background: Colors.indigo.shade50,
                                              foreground: Colors.indigo.shade700,
                                              borderColor: Colors.indigo.shade100,
                                            ),
                                            _buildStatPill(
                                              icon: Icons.local_fire_department_rounded,
                                              text: "${habit['streak'] ?? 0} Streak",
                                              background: Colors.orange.shade50,
                                              foreground: Colors.orange.shade700,
                                              borderColor: Colors.orange.shade100,
                                            ),
                                            _buildStatPill(
                                              icon: Icons.star_rounded,
                                              text: "$displayedXp XP",
                                              background: Colors.green.shade50,
                                              foreground: Colors.green.shade700,
                                              borderColor: Colors.green.shade100,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _showLifetime
                                              ? "Lifetime total"
                                              : _intervalLabel,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.grey.shade200,
                                      ),
                                    ),
                                    child: IconButton(
                                      icon: Icon(
                                        Icons.insights_rounded,
                                        color: Colors.indigo.shade600,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (_) => _HabitHistoryDialog(
                                            habitId: habit['id'],
                                            habitTitle: habit['title'],
                                            habitType: habitType,
                                            unit: habitUnit,
                                            targetUserId: widget.targetUserId,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleText(String text, bool isSelected) {
    return Center(
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 200),
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 13,
          color: isSelected ? Colors.indigo.shade700 : Colors.grey.shade600,
        ),
        child: Text(text),
      ),
    );
  }

  Widget _buildStatBadge(IconData icon, String text, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade100),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color.shade700),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color.shade800,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 🔥 Habit History Dialog (Timeline View)
// ==========================================

class _HabitHistoryDialog extends StatefulWidget {
  final String habitId;
  final String habitTitle;
  final String habitType;
  final String unit;
  final String targetUserId;

  const _HabitHistoryDialog({
    required this.habitId,
    required this.habitTitle,
    required this.habitType,
    required this.unit,
    required this.targetUserId,
  });

  @override
  State<_HabitHistoryDialog> createState() => _HabitHistoryDialogState();
}

class _HabitHistoryDialogState extends State<_HabitHistoryDialog> {
  bool _loading = true;
  List<Map<String, dynamic>> _sessions = [];

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    try {
      final response = await Supabase.instance.client
          .from('habit_sessions')
          .select('value, started_at, flow_points')
          .eq('habit_id', widget.habitId)
          .eq('user_id', widget.targetUserId)
          .order('started_at', ascending: false)
          .limit(10);

      if (mounted) {
        setState(() {
          _sessions = List<Map<String, dynamic>>.from(response);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint("Failed to fetch habit history: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatHabitValue(double value, String type, String unit) {
    if (value <= 0) return '';
    if (type == 'duration') {
      String lUnit = unit.toLowerCase();
      if (lUnit == 'minutes' || lUnit == 'min') {
        int totalSeconds = (value * 60).round();
        if (totalSeconds < 60) return '+ $totalSeconds sec';
        int m = totalSeconds ~/ 60;
        int s = totalSeconds % 60;
        if (s == 0) return '+ $m min';
        return '+ $m min $s sec';
      } else if (lUnit == 'hours' || lUnit == 'hr') {
        int totalMinutes = (value * 60).round();
        if (totalMinutes < 60) return '+ $totalMinutes min';
        int h = totalMinutes ~/ 60;
        int m = totalMinutes % 60;
        if (m == 0) return '+ $h hr';
        return '+ $h hr $m min';
      } else {
        return '+ ${value.toInt()} sec';
      }
    }
    if (value % 1 == 0) return '+ ${value.toInt()} $unit';
    return '+ ${value.toStringAsFixed(1)} $unit';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.all(20),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.history_rounded,
                    color: Colors.indigo.shade600,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Activity Timeline",
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        widget.habitTitle,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32.0),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32.0),
                child: Center(
                  child: Text(
                    "No recent logs found.",
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _sessions.length,
                  itemBuilder: (context, index) {
                    final session = _sessions[index];
                    final date = DateTime.parse(session['started_at']).toLocal();
                    final xp = session['flow_points'] ?? 0;
                    
                    final rawValue = session['value'] ?? 0;
                    double activityValue = 0;
                    if (rawValue is num) {
                      activityValue = rawValue.toDouble();
                    } else {
                      activityValue = double.tryParse(rawValue.toString()) ?? 0;
                    }
                    String valueLabel = _formatHabitValue(activityValue, widget.habitType, widget.unit);

                    String timeStr =
                        "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
                    String dateStr =
                        "${date.day}/${date.month}/${date.year}";

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.indigo.shade400,
                                  width: 3,
                                ),
                              ),
                            ),
                            if (index != _sessions.length - 1)
                              Container(
                                width: 2,
                                height: 40, 
                                color: Colors.indigo.shade100,
                              ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      dateStr,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      "At $timeStr",
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (valueLabel.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        valueLabel,
                                        style: TextStyle(
                                          color: Colors.indigo.shade600,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ]
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.green.shade100,
                                    ),
                                  ),
                                  child: Text(
                                    "+$xp XP",
                                    style: TextStyle(
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.grey.shade100,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  "Close",
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}