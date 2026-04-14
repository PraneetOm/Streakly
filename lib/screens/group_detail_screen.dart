import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/group_service.dart';
import 'group_admin_screen.dart';
import 'group_leaderboard_screen.dart';
import 'group_chat_screen.dart';

class GroupDetailScreen extends StatefulWidget {
  final Map<String, dynamic> group;

  const GroupDetailScreen({super.key, required this.group});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  final GroupService _svc = GroupService();
  final _supabase = Supabase.instance.client;

  // 🔥 NEW: This key allows the top button to trigger the swipe-down animation!
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();

  bool _loading = true;
  bool _loadingActivity = true;

  int memberCount = 0;
  String? _userId;
  String? memberRole;
  String? memberStatus;

  String? _actualOwnerId;

  List<Map<String, dynamic>> _activity = [];

  @override
  void initState() {
    super.initState();
    _userId = _supabase.auth.currentUser?.id;
    _loadData();
    _loadActivity();
  }

  // 🔥 UPGRADED: Added isRefresh flag to prevent the screen from going blank on pull-to-refresh
  Future<void> _loadData({bool isRefresh = false}) async {
    if (!isRefresh) setState(() => _loading = true);
    
    try {
      final groupData = await _supabase
          .from('groups')
          .select('owner_id')
          .eq('id', widget.group['id'])
          .maybeSingle();

      if (groupData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: const Text("This group no longer exists.", style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.red.shade600),
          );
          Navigator.pop(context, true);
        }
        return;
      }

      _actualOwnerId = groupData['owner_id']?.toString();

      final members = await _svc.getGroupMembers(widget.group['id']);
      memberCount = members.length;

      final me = members.where((m) => m['user_id'] == _userId).toList();
      
      if (me.isNotEmpty) {
        memberRole = me.first['role'];
        memberStatus = me.first['status'];
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("You have been removed from this group.", style: TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: Colors.red.shade600,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
          Navigator.pop(context, true); 
        }
        return;
      }
    } catch (e) {
      debugPrint('Error loading group: $e');
    } finally {
      if (mounted) {
        if (!isRefresh) setState(() => _loading = false);
        else setState(() {}); // Just rebuild UI silently with new data
      }
    }
  }

  // 🔥 UPGRADED: Added isRefresh flag
  Future<void> _loadActivity({bool isRefresh = false}) async {
    if (!isRefresh) setState(() => _loadingActivity = true);
    
    try {
      _activity = await _svc.getGroupActivity(widget.group['id']);
    } catch (e) {
      debugPrint('Error loading activity: $e');
      _activity = [];
    } finally {
      if (mounted) {
        if (!isRefresh) setState(() => _loadingActivity = false);
        else setState(() {});
      }
    }
  }

  bool get isOwner => _actualOwnerId == _userId;
  bool get isAdmin => memberRole == 'admin' || memberRole == 'owner';

  // --- LEAVE GROUP ---
  Future<bool> _confirmLeave() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 8),
            Text('Leave group?', style: TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        content: Text(
          'Are you sure you want to leave this group? You can join again later if it is open or if you have the code.',
          style: TextStyle(color: Colors.grey.shade700, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // --- ABANDON GROUP ---
  Future<bool> _confirmAbandon() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 28),
            const SizedBox(width: 8),
            const Text('Abandon Group?', style: TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        content: Text(
          'If you abandon this group, ownership will automatically transfer to the member with the highest XP.\n\nIf you are the only member, the group will be deleted permanently. Are you sure?',
          style: TextStyle(color: Colors.grey.shade700, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Abandon', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _abandonGroup() async {
    setState(() => _loading = true);
    try {
      await _svc.abandonGroup(widget.group['id'], _userId!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('You have abandoned the group.', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Abandon error: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to abandon group: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final privacy = (g['privacy'] ?? 'public').toString();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        centerTitle: true,
        title: Text(
          g['name'] ?? 'Group Details',
          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w900, letterSpacing: -0.5),
        ),
        actions: [
          // 🔥 NEW: Explicit Refresh Button
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.04),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 22, color: Colors.black87),
              onPressed: () {
                // This magically triggers the pull-to-refresh spinner programmatically!
                _refreshIndicatorKey.currentState?.show();
              },
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              key: _refreshIndicatorKey, // 🔥 Attach the key
              color: Colors.indigo.shade600,
              backgroundColor: Colors.white,
              onRefresh: () async {
                // 🔥 Wait for both to finish silently
                await Future.wait([
                  _loadData(isRefresh: true),
                  _loadActivity(isRefresh: true),
                ]);
              },
              child: SingleChildScrollView(
                // 🔥 THE FIX: Guarantees pull-to-refresh works even if content is shorter than the screen!
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // HERO HEADER
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Colors.indigo.shade600, Colors.indigo.shade800],
                        ),
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(color: Colors.indigo.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 10)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
                                ),
                                child: Center(
                                  child: Text(
                                    (g['name'] ?? 'G').toString()[0].toUpperCase(),
                                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      g['name'] ?? '',
                                      style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      g['description'] ?? 'No description provided.',
                                      style: TextStyle(color: Colors.indigo.shade100, fontSize: 14, height: 1.4, fontWeight: FontWeight.w500),
                                      maxLines: 2, overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _buildGlassyChip(Icons.lock_outline_rounded, privacy.toUpperCase()),
                              _buildGlassyChip(Icons.people_alt_rounded, '$memberCount Members'),
                              _buildGlassyChip(Icons.shield_rounded, isOwner ? 'OWNER' : (memberRole ?? 'MEMBER').toUpperCase()),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // QUICK ACTIONS
                    const Text("Group Hub", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: -0.5)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildColorActionCard(
                            icon: Icons.leaderboard_rounded,
                            title: 'Rankings',
                            subtitle: 'View Leaderboard',
                            color: Colors.amber,
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GroupLeaderboardScreen(groupId: g['id'], groupName: g['name'] ?? 'Group'))),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildColorActionCard(
                            icon: Icons.chat_bubble_rounded,
                            title: 'Chat',
                            subtitle: 'Group Messages',
                            color: Colors.teal,
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: g['id'], groupName: g['name'] ?? 'Group'))),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (isOwner || isAdmin)
                      _buildColorActionCard(
                        icon: Icons.admin_panel_settings_rounded,
                        title: 'Admin Settings',
                        subtitle: 'Manage members, requests, and group info',
                        color: Colors.purple,
                        isFullWidth: true,
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => GroupAdminScreen(groupId: g['id'])));
                          // Silent refresh upon return from admin settings
                          _refreshIndicatorKey.currentState?.show();
                        },
                      ),

                    const SizedBox(height: 32),

                    // ACTIVITY FEED
                    const Text("Live Activity", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: -0.5)),
                    const SizedBox(height: 16),
                    _loadingActivity
                        ? const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                        : _activity.isEmpty
                            ? _buildEmptyActivity()
                            : Column(
                                children: _activity.take(8).map((item) => _buildActivityItem(item)).toList(),
                              ),

                    const SizedBox(height: 40),

                    // DANGER ZONE
                    if (isOwner)
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.warning_amber_rounded, size: 20),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade50,
                            foregroundColor: Colors.red.shade700,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.red.shade200, width: 2)),
                          ),
                          onPressed: () async {
                            final ok = await _confirmAbandon();
                            if (ok) await _abandonGroup();
                          },
                          label: const Text('Abandon Group', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        ),
                      )
                    else if (memberStatus == 'active')
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.exit_to_app_rounded, size: 20),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade50,
                            foregroundColor: Colors.red.shade700,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.red.shade100, width: 2)),
                          ),
                          onPressed: () async {
                            final ok = await _confirmLeave();
                            if (!ok) return;
                            await _svc.leaveGroup(_userId, widget.group['id']);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Left group', style: TextStyle(fontWeight: FontWeight.bold))));
                            Navigator.pop(context, true);
                          },
                          label: const Text('Leave Group', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        ),
                      ),
                      
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildGlassyChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _buildColorActionCard({required IconData icon, required String title, required String subtitle, required MaterialColor color, required VoidCallback onTap, bool isFullWidth = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: isFullWidth 
          ? Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(16)),
                  child: Icon(icon, color: color.shade600, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black87)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade300),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(16)),
                  child: Icon(icon, color: color.shade600, size: 28),
                ),
                const SizedBox(height: 16),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black87)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
      ),
    );
  }

  Widget _buildActivityItem(Map<String, dynamic> item) {
    final type = item['activity_type']?.toString();
    final title = (item['title'] ?? '').toString();
    final body = (item['body'] ?? '').toString();
    final xp = (item['xp_earned'] ?? 0) as int;

    IconData iconData;
    Color iconColor;
    Color bgColor;

    switch (type) {
      case 'habit_completed':
        iconData = Icons.check_circle_rounded;
        iconColor = Colors.green.shade600;
        bgColor = Colors.green.shade50;
        break;
      case 'rank_changed':
        iconData = Icons.workspace_premium_rounded;
        iconColor = Colors.amber.shade600;
        bgColor = Colors.amber.shade50;
        break;
      case 'joined':
        iconData = Icons.waving_hand_rounded;
        iconColor = Colors.blue.shade600;
        bgColor = Colors.blue.shade50;
        break;
      case 'promoted':
        iconData = Icons.shield_rounded;
        iconColor = Colors.purple.shade600;
        bgColor = Colors.purple.shade50;
        break;
      case 'nudge':
        iconData = Icons.notifications_active_rounded;
        iconColor = Colors.orange.shade600;
        bgColor = Colors.orange.shade50;
        break;
      case 'high_five':
        iconData = Icons.pan_tool_rounded;
        iconColor = Colors.teal.shade600;
        bgColor = Colors.teal.shade50;
        break;
      default:
        iconData = Icons.bolt_rounded;
        iconColor = Colors.indigo.shade600;
        bgColor = Colors.indigo.shade50;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
            child: Icon(iconData, color: iconColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.black87)),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(body, style: TextStyle(color: Colors.grey.shade600, height: 1.3, fontSize: 13, fontWeight: FontWeight.w500)),
                ],
              ],
            ),
          ),
          if (xp > 0)
            Container(
              margin: const EdgeInsets.only(left: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
              child: Text('+$xp XP', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w900, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyActivity() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200, style: BorderStyle.solid),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.grey.shade50, shape: BoxShape.circle),
            child: Icon(Icons.history_toggle_off_rounded, size: 32, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 16),
          Text('Quiet in here...', style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 6),
          Text(
            'Updates like new members joining, high-fives, and habit streaks will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontWeight: FontWeight.w500, height: 1.4),
          ),
        ],
      ),
    );
  }
}

// import 'package:flutter/material.dart';
// import 'package:supabase_flutter/supabase_flutter.dart';
// import '../services/group_service.dart';
// import 'group_admin_screen.dart';
// import 'group_leaderboard_screen.dart';
// import 'group_chat_screen.dart';

// class GroupDetailScreen extends StatefulWidget {
//   final Map<String, dynamic> group;

//   const GroupDetailScreen({super.key, required this.group});

//   @override
//   State<GroupDetailScreen> createState() => _GroupDetailScreenState();
// }

// class _GroupDetailScreenState extends State<GroupDetailScreen> {
//   final GroupService _svc = GroupService();
//   final _supabase = Supabase.instance.client;

//   bool _loading = true;
//   bool _loadingActivity = true;

//   int memberCount = 0;
//   String? _userId;
//   String? memberRole;
//   String? memberStatus;

//   // 🔥 Store the TRUE owner ID directly from the database
//   String? _actualOwnerId;

//   List<Map<String, dynamic>> _activity = [];

//   @override
//   void initState() {
//     super.initState();
//     _userId = _supabase.auth.currentUser?.id;
//     _loadData();
//     _loadActivity();
//   }

//   Future<void> _loadData() async {
//     setState(() => _loading = true);
//     try {
//       final groupData = await _supabase
//           .from('groups')
//           .select('owner_id')
//           .eq('id', widget.group['id'])
//           .maybeSingle();

//       if (groupData == null) {
//         if (mounted) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(content: const Text("This group no longer exists.", style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.red.shade600),
//           );
//           Navigator.pop(context, true);
//         }
//         return;
//       }

//       _actualOwnerId = groupData['owner_id']?.toString();

//       final members = await _svc.getGroupMembers(widget.group['id']);
//       memberCount = members.length;

//       final me = members.where((m) => m['user_id'] == _userId).toList();
      
//       if (me.isNotEmpty) {
//         memberRole = me.first['role'];
//         memberStatus = me.first['status'];
//       } else {
//         if (mounted) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(
//               content: const Text("You have been removed from this group.", style: TextStyle(fontWeight: FontWeight.bold)),
//               backgroundColor: Colors.red.shade600,
//               behavior: SnackBarBehavior.floating,
//               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//             ),
//           );
//           Navigator.pop(context, true); 
//         }
//         return;
//       }
//     } catch (e) {
//       debugPrint('Error loading group: $e');
//     } finally {
//       if (mounted) setState(() => _loading = false);
//     }
//   }

//   Future<void> _loadActivity() async {
//     setState(() => _loadingActivity = true);
//     try {
//       _activity = await _svc.getGroupActivity(widget.group['id']);
//     } catch (e) {
//       debugPrint('Error loading activity: $e');
//       _activity = [];
//     } finally {
//       if (mounted) setState(() => _loadingActivity = false);
//     }
//   }

//   bool get isOwner => _actualOwnerId == _userId;
//   bool get isAdmin => memberRole == 'admin' || memberRole == 'owner';

//   // --- LEAVE GROUP ---
//   Future<bool> _confirmLeave() async {
//     final result = await showDialog<bool>(
//       context: context,
//       builder: (_) => AlertDialog(
//         backgroundColor: Colors.white,
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
//         title: const Row(
//           children: [
//             Icon(Icons.logout_rounded, color: Colors.redAccent, size: 28),
//             SizedBox(width: 8),
//             Text('Leave group?', style: TextStyle(fontWeight: FontWeight.w900)),
//           ],
//         ),
//         content: Text(
//           'Are you sure you want to leave this group? You can join again later if it is open or if you have the code.',
//           style: TextStyle(color: Colors.grey.shade700, height: 1.4),
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context, false),
//             child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
//           ),
//           ElevatedButton(
//             style: ElevatedButton.styleFrom(
//               backgroundColor: Colors.red.shade600,
//               foregroundColor: Colors.white,
//               elevation: 0,
//               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//             ),
//             onPressed: () => Navigator.pop(context, true),
//             child: const Text('Leave', style: TextStyle(fontWeight: FontWeight.bold)),
//           ),
//         ],
//       ),
//     );
//     return result ?? false;
//   }

//   // --- ABANDON GROUP ---
//   Future<bool> _confirmAbandon() async {
//     final result = await showDialog<bool>(
//       context: context,
//       builder: (_) => AlertDialog(
//         backgroundColor: Colors.white,
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
//         title: Row(
//           children: [
//             Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 28),
//             const SizedBox(width: 8),
//             const Text('Abandon Group?', style: TextStyle(fontWeight: FontWeight.w900)),
//           ],
//         ),
//         content: Text(
//           'If you abandon this group, ownership will automatically transfer to the member with the highest XP.\n\nIf you are the only member, the group will be deleted permanently. Are you sure?',
//           style: TextStyle(color: Colors.grey.shade700, height: 1.4),
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context, false),
//             child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
//           ),
//           ElevatedButton(
//             style: ElevatedButton.styleFrom(
//               backgroundColor: Colors.red.shade700,
//               foregroundColor: Colors.white,
//               elevation: 0,
//               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//             ),
//             onPressed: () => Navigator.pop(context, true),
//             child: const Text('Abandon', style: TextStyle(fontWeight: FontWeight.bold)),
//           ),
//         ],
//       ),
//     );
//     return result ?? false;
//   }

//   Future<void> _abandonGroup() async {
//     setState(() => _loading = true);
//     try {
//       await _svc.abandonGroup(widget.group['id'], _userId!);
//       if (!mounted) return;
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: const Text('You have abandoned the group.', style: TextStyle(fontWeight: FontWeight.bold)),
//           backgroundColor: Colors.orange.shade700,
//           behavior: SnackBarBehavior.floating,
//         ),
//       );
//       Navigator.pop(context, true);
//     } catch (e) {
//       debugPrint('Abandon error: $e');
//       if (mounted) {
//         setState(() => _loading = false);
//         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to abandon group: $e')));
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final g = widget.group;
//     final privacy = (g['privacy'] ?? 'public').toString();

//     return Scaffold(
//       backgroundColor: const Color(0xFFF4F6F9), // Sleek off-white background
//       appBar: AppBar(
//         backgroundColor: Colors.transparent,
//         elevation: 0,
//         iconTheme: const IconThemeData(color: Colors.black87),
//         centerTitle: true,
//         title: Text(
//           g['name'] ?? 'Group Details',
//           style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w900, letterSpacing: -0.5),
//         ),
//       ),
//       body: _loading
//           ? const Center(child: CircularProgressIndicator())
//           : RefreshIndicator(
//               onRefresh: () async {
//                 await _loadData();
//                 await _loadActivity();
//               },
//               child: SingleChildScrollView(
//                 physics: const BouncingScrollPhysics(),
//                 padding: const EdgeInsets.all(20),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     // 🔥 HERO HEADER
//                     Container(
//                       padding: const EdgeInsets.all(24),
//                       decoration: BoxDecoration(
//                         gradient: LinearGradient(
//                           begin: Alignment.topLeft,
//                           end: Alignment.bottomRight,
//                           colors: [Colors.indigo.shade600, Colors.indigo.shade800],
//                         ),
//                         borderRadius: BorderRadius.circular(32),
//                         boxShadow: [
//                           BoxShadow(color: Colors.indigo.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 10)),
//                         ],
//                       ),
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Row(
//                             children: [
//                               Container(
//                                 width: 64,
//                                 height: 64,
//                                 decoration: BoxDecoration(
//                                   color: Colors.white.withValues(alpha: 0.2),
//                                   shape: BoxShape.circle,
//                                   border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
//                                 ),
//                                 child: Center(
//                                   child: Text(
//                                     (g['name'] ?? 'G').toString()[0].toUpperCase(),
//                                     style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
//                                   ),
//                                 ),
//                               ),
//                               const SizedBox(width: 16),
//                               Expanded(
//                                 child: Column(
//                                   crossAxisAlignment: CrossAxisAlignment.start,
//                                   children: [
//                                     Text(
//                                       g['name'] ?? '',
//                                       style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5),
//                                       maxLines: 1, overflow: TextOverflow.ellipsis,
//                                     ),
//                                     const SizedBox(height: 6),
//                                     Text(
//                                       g['description'] ?? 'No description provided.',
//                                       style: TextStyle(color: Colors.indigo.shade100, fontSize: 14, height: 1.4, fontWeight: FontWeight.w500),
//                                       maxLines: 2, overflow: TextOverflow.ellipsis,
//                                     ),
//                                   ],
//                                 ),
//                               ),
//                             ],
//                           ),
//                           const SizedBox(height: 24),
//                           Wrap(
//                             spacing: 10,
//                             runSpacing: 10,
//                             children: [
//                               _buildGlassyChip(Icons.lock_outline_rounded, privacy.toUpperCase()),
//                               _buildGlassyChip(Icons.people_alt_rounded, '$memberCount Members'),
//                               _buildGlassyChip(Icons.shield_rounded, isOwner ? 'OWNER' : (memberRole ?? 'MEMBER').toUpperCase()),
//                             ],
//                           ),
//                         ],
//                       ),
//                     ),
//                     const SizedBox(height: 28),

//                     // 🔥 QUICK ACTIONS
//                     const Text("Group Hub", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: -0.5)),
//                     const SizedBox(height: 16),
//                     Row(
//                       children: [
//                         Expanded(
//                           child: _buildColorActionCard(
//                             icon: Icons.leaderboard_rounded,
//                             title: 'Rankings',
//                             subtitle: 'View Leaderboard',
//                             color: Colors.amber,
//                             onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GroupLeaderboardScreen(groupId: g['id'], groupName: g['name'] ?? 'Group'))),
//                           ),
//                         ),
//                         const SizedBox(width: 12),
//                         Expanded(
//                           child: _buildColorActionCard(
//                             icon: Icons.chat_bubble_rounded,
//                             title: 'Chat',
//                             subtitle: 'Group Messages',
//                             color: Colors.teal,
//                             onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: g['id'], groupName: g['name'] ?? 'Group'))),
//                           ),
//                         ),
//                       ],
//                     ),
//                     const SizedBox(height: 12),
//                     if (isOwner || isAdmin)
//                       _buildColorActionCard(
//                         icon: Icons.admin_panel_settings_rounded,
//                         title: 'Admin Settings',
//                         subtitle: 'Manage members, requests, and group info',
//                         color: Colors.purple,
//                         isFullWidth: true,
//                         onTap: () async {
//                           await Navigator.push(context, MaterialPageRoute(builder: (_) => GroupAdminScreen(groupId: g['id'])));
//                           _loadData();
//                           _loadActivity();
//                         },
//                       ),

//                     const SizedBox(height: 32),

//                     // 🔥 ACTIVITY FEED
//                     const Text("Live Activity", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: -0.5)),
//                     const SizedBox(height: 16),
//                     _loadingActivity
//                         ? const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
//                         : _activity.isEmpty
//                             ? _buildEmptyActivity()
//                             : Column(
//                                 children: _activity.take(8).map((item) => _buildActivityItem(item)).toList(),
//                               ),

//                     const SizedBox(height: 40),

//                     // 🔥 DANGER ZONE
//                     if (isOwner)
//                       SizedBox(
//                         width: double.infinity,
//                         height: 56,
//                         child: ElevatedButton.icon(
//                           icon: const Icon(Icons.warning_amber_rounded, size: 20),
//                           style: ElevatedButton.styleFrom(
//                             backgroundColor: Colors.red.shade50,
//                             foregroundColor: Colors.red.shade700,
//                             elevation: 0,
//                             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.red.shade200, width: 2)),
//                           ),
//                           onPressed: () async {
//                             final ok = await _confirmAbandon();
//                             if (ok) await _abandonGroup();
//                           },
//                           label: const Text('Abandon Group', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
//                         ),
//                       )
//                     else if (memberStatus == 'active')
//                       SizedBox(
//                         width: double.infinity,
//                         height: 56,
//                         child: ElevatedButton.icon(
//                           icon: const Icon(Icons.exit_to_app_rounded, size: 20),
//                           style: ElevatedButton.styleFrom(
//                             backgroundColor: Colors.red.shade50,
//                             foregroundColor: Colors.red.shade700,
//                             elevation: 0,
//                             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.red.shade100, width: 2)),
//                           ),
//                           onPressed: () async {
//                             final ok = await _confirmLeave();
//                             if (!ok) return;
//                             await _svc.leaveGroup(_userId, widget.group['id']);
//                             if (!mounted) return;
//                             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Left group', style: TextStyle(fontWeight: FontWeight.bold))));
//                             Navigator.pop(context, true);
//                           },
//                           label: const Text('Leave Group', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
//                         ),
//                       ),
                      
//                     const SizedBox(height: 40),
//                   ],
//                 ),
//               ),
//             ),
//     );
//   }

//   Widget _buildGlassyChip(IconData icon, String text) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
//       decoration: BoxDecoration(
//         color: Colors.white.withValues(alpha: 0.15),
//         borderRadius: BorderRadius.circular(8),
//         border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
//       ),
//       child: Row(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           Icon(icon, size: 14, color: Colors.white),
//           const SizedBox(width: 6),
//           Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5)),
//         ],
//       ),
//     );
//   }

//   Widget _buildColorActionCard({required IconData icon, required String title, required String subtitle, required MaterialColor color, required VoidCallback onTap, bool isFullWidth = false}) {
//     return InkWell(
//       onTap: onTap,
//       borderRadius: BorderRadius.circular(24),
//       child: Container(
//         padding: const EdgeInsets.all(16),
//         decoration: BoxDecoration(
//           color: Colors.white,
//           borderRadius: BorderRadius.circular(24),
//           border: Border.all(color: Colors.grey.shade200),
//           boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
//         ),
//         child: isFullWidth 
//           ? Row(
//               children: [
//                 Container(
//                   padding: const EdgeInsets.all(12),
//                   decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(16)),
//                   child: Icon(icon, color: color.shade600, size: 28),
//                 ),
//                 const SizedBox(width: 16),
//                 Expanded(
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black87)),
//                       const SizedBox(height: 4),
//                       Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.bold)),
//                     ],
//                   ),
//                 ),
//                 Icon(Icons.chevron_right_rounded, color: Colors.grey.shade300),
//               ],
//             )
//           : Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Container(
//                   padding: const EdgeInsets.all(12),
//                   decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(16)),
//                   child: Icon(icon, color: color.shade600, size: 28),
//                 ),
//                 const SizedBox(height: 16),
//                 Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black87)),
//                 const SizedBox(height: 4),
//                 Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.bold)),
//               ],
//             ),
//       ),
//     );
//   }

//   Widget _buildActivityItem(Map<String, dynamic> item) {
//     final type = item['activity_type']?.toString();
//     final title = (item['title'] ?? '').toString();
//     final body = (item['body'] ?? '').toString();
//     final xp = (item['xp_earned'] ?? 0) as int;

//     IconData iconData;
//     Color iconColor;
//     Color bgColor;

//     switch (type) {
//       case 'habit_completed':
//         iconData = Icons.check_circle_rounded;
//         iconColor = Colors.green.shade600;
//         bgColor = Colors.green.shade50;
//         break;
//       case 'rank_changed':
//         iconData = Icons.workspace_premium_rounded;
//         iconColor = Colors.amber.shade600;
//         bgColor = Colors.amber.shade50;
//         break;
//       case 'joined':
//         iconData = Icons.waving_hand_rounded;
//         iconColor = Colors.blue.shade600;
//         bgColor = Colors.blue.shade50;
//         break;
//       case 'promoted':
//         iconData = Icons.shield_rounded;
//         iconColor = Colors.purple.shade600;
//         bgColor = Colors.purple.shade50;
//         break;
//       case 'nudge':
//         iconData = Icons.notifications_active_rounded;
//         iconColor = Colors.orange.shade600;
//         bgColor = Colors.orange.shade50;
//         break;
//       case 'high_five':
//         iconData = Icons.pan_tool_rounded;
//         iconColor = Colors.teal.shade600;
//         bgColor = Colors.teal.shade50;
//         break;
//       default:
//         iconData = Icons.bolt_rounded;
//         iconColor = Colors.indigo.shade600;
//         bgColor = Colors.indigo.shade50;
//     }

//     return Container(
//       margin: const EdgeInsets.only(bottom: 12),
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(20),
//         border: Border.all(color: Colors.grey.shade200),
//         boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
//       ),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Container(
//             padding: const EdgeInsets.all(10),
//             decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
//             child: Icon(iconData, color: iconColor, size: 20),
//           ),
//           const SizedBox(width: 16),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.black87)),
//                 if (body.isNotEmpty) ...[
//                   const SizedBox(height: 4),
//                   Text(body, style: TextStyle(color: Colors.grey.shade600, height: 1.3, fontSize: 13, fontWeight: FontWeight.w500)),
//                 ],
//               ],
//             ),
//           ),
//           if (xp > 0)
//             Container(
//               margin: const EdgeInsets.only(left: 12),
//               padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//               decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
//               child: Text('+$xp XP', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w900, fontSize: 12)),
//             ),
//         ],
//       ),
//     );
//   }

//   Widget _buildEmptyActivity() {
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(24),
//         border: Border.all(color: Colors.grey.shade200, style: BorderStyle.solid),
//       ),
//       child: Column(
//         children: [
//           Container(
//             padding: const EdgeInsets.all(16),
//             decoration: BoxDecoration(color: Colors.grey.shade50, shape: BoxShape.circle),
//             child: Icon(Icons.history_toggle_off_rounded, size: 32, color: Colors.grey.shade400),
//           ),
//           const SizedBox(height: 16),
//           Text('Quiet in here...', style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w900, fontSize: 16)),
//           const SizedBox(height: 6),
//           Text(
//             'Updates like new members joining, high-fives, and habit streaks will appear here.',
//             textAlign: TextAlign.center,
//             style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontWeight: FontWeight.w500, height: 1.4),
//           ),
//         ],
//       ),
//     );
//   }
// }