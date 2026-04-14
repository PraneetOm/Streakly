import 'package:flutter/material.dart';
import 'package:newapp/screens/group_detail_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/group_service.dart';
import 'create_group_screen.dart';

class GroupListScreen extends StatefulWidget {
  const GroupListScreen({super.key});

  @override
  State<GroupListScreen> createState() => _GroupListScreenState();
}

class _GroupListScreenState extends State<GroupListScreen> {
  final _supabase = Supabase.instance.client;
  final GroupService _svc = GroupService();

  final _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  bool _loading = false;

  // 🔥 Split lists for the two tabs
  List<Map<String, dynamic>> _myGroups = [];
  List<Map<String, dynamic>> _discoverGroups = [];

  int _selectedTab = 0; // 0 = My Groups, 1 = Discover
  String? _userId;

  @override
  void initState() {
    super.initState();
    _userId = _supabase.auth.currentUser?.id;
    _loadGroups();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose(); // 🔥 Clean up the focus node
    super.dispose();
  }

  Future<void> _loadGroups({String? query}) async {
    setState(() => _loading = true);
    try {
      // 1) Fetch ALL public groups
      final publicResp = await _supabase
          .from('groups')
          .select(
            'id, name, description, privacy, owner_id, join_code, created_at',
          )
          .eq('privacy', 'public')
          .order('created_at', ascending: false);

      // 2) Fetch groups the user is ACTUALLY a member of
      List<Map<String, dynamic>> memberGroups = [];
      if (_userId != null) {
        final memResp = await _supabase
            .from('group_members')
            .select(
              'group_id, role, status, groups!inner(id, name, description, privacy, owner_id, join_code, created_at)',
            )
            .eq('user_id', _userId!)
            .inFilter('status', ['active', 'pending']);

        final rows = (memResp as List).cast<Map<String, dynamic>>();

        for (final r in rows) {
          final g = r['groups'];
          if (g != null) {
            final group = Map<String, dynamic>.from(g);
            group['member_role'] = r['role'];
            group['member_status'] = r['status'];
            memberGroups.add(group);
          }
        }
      }

      List<Map<String, dynamic>> rawPublicGroups = (publicResp as List)
          .cast<Map<String, dynamic>>();

      // 3) Filter out groups the user is already in from the Discover list
      final myGroupIds = memberGroups.map((g) => g['id'].toString()).toSet();
      List<Map<String, dynamic>> discoverGroups = rawPublicGroups.where((g) {
        return !myGroupIds.contains(g['id'].toString());
      }).toList();

      // 4) Apply Search Query to both lists
      if (query != null && query.trim().isNotEmpty) {
        final q = query.toLowerCase();
        memberGroups = memberGroups.where((g) {
          return (g['name'] ?? '').toLowerCase().contains(q) ||
              (g['description'] ?? '').toLowerCase().contains(q);
        }).toList();

        discoverGroups = discoverGroups.where((g) {
          return (g['name'] ?? '').toLowerCase().contains(q) ||
              (g['description'] ?? '').toLowerCase().contains(q);
        }).toList();
      }

      setState(() {
        _myGroups = memberGroups;
        _discoverGroups = discoverGroups;
      });
    } catch (e) {
      debugPrint('load groups error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _joinByCodeDialog() async {
    _searchFocus.unfocus();
    final codeCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Enter Invite Code',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: codeCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Group Code',
              hintText: 'e.g. AB12CD',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
              prefixIcon: const Icon(Icons.key_rounded),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter a valid code' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );

    if (res == true) {
      await _joinByCode(codeCtrl.text.trim());
    }
  }

  Future<void> _joinByCode(String code) async {
    if (_userId == null) return;
    setState(() => _loading = true);

    try {
      final data = await _supabase
          .from('groups')
          .select('id, name, privacy, owner_id')
          .eq('join_code', code)
          .maybeSingle();

      if (data == null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Invalid code')));
        }
        return;
      }

      final groupId = data['id'];
      final privacy = data['privacy'] ?? 'public';

      final existing = await _supabase
          .from('group_members')
          .select()
          .eq('group_id', groupId)
          .eq('user_id', _userId!)
          .maybeSingle();

      if (existing != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You are already in this group.')),
          );
        }
        return;
      }

      final status = privacy == 'public' ? 'active' : 'pending';

      await _supabase.from('group_members').insert({
        'group_id': groupId,
        'user_id': _userId,
        'status': status,
        'role': 'member',
      });

      if (status == 'active') {
        final userName = await _svc.getMyDisplayName(_userId!);
        await _svc.addGroupActivity(
          groupId: groupId,
          actorUserId: _userId!,
          actorName: userName,
          activityType: 'joined',
          title: '$userName joined via invite code',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              privacy == 'public'
                  ? 'Successfully joined!'
                  : 'Join request sent.',
            ),
          ),
        );
      }
      await _loadGroups();
    } catch (e) {
      debugPrint('join error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _joinPublicGroup(String groupId) async {
    if (_userId == null) return;
    setState(() => _loading = true);

    try {
      await _supabase.from('group_members').insert({
        'group_id': groupId,
        'user_id': _userId,
        'role': 'member',
        'status': 'active',
      });

      final userName = await _svc.getMyDisplayName(_userId!);
      await _svc.addGroupActivity(
        groupId: groupId,
        actorUserId: _userId!,
        actorName: userName,
        activityType: 'joined',
        title: '$userName joined the group',
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Joined successfully!')));
      }

      // Auto-switch back to "My Groups" tab after joining
      setState(() => _selectedTab = 0);
      await _loadGroups();
    } catch (e) {
      debugPrint('join public error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildGroupTile(Map<String, dynamic> g) {
    final name = g['name'] ?? 'Unnamed Group';
    final desc = g['description'] ?? '';
    final privacy = g['privacy'] ?? 'public';
    final memberStatus = g['member_status'] as String?;
    final memberRole = g['member_role'] as String?;

    final bool isTrueOwner = (g['owner_id'] == _userId) && (memberRole != null);
    final isMember = memberStatus == 'active' || memberStatus == 'pending';

    String buttonText() {
      if (isTrueOwner) return 'Manage';
      if (memberRole == 'admin') return 'Open Group';
      if (isMember && memberStatus == 'active') return 'Open Group';
      if (isMember && memberStatus == 'pending') return 'Pending';
      return 'View & Join';
    }

    Color buttonColor() {
      if (isTrueOwner) return Colors.indigo.shade600;
      if (memberRole == 'admin') return Colors.indigo.shade500;
      if (isMember && memberStatus == 'active') return Colors.indigo.shade500;
      if (isMember && memberStatus == 'pending') return Colors.orange.shade400;
      return Colors.green.shade600;
    }

    IconData buttonIcon() {
      if (isTrueOwner) return Icons.settings_outlined;
      if (isMember && memberStatus == 'active') {
        return Icons.arrow_forward_rounded;
      }
      if (isMember && memberStatus == 'pending') {
        return Icons.hourglass_empty_rounded;
      }
      return Icons.travel_explore_rounded;
    }

    Future<void> handleAction() async {
      _searchFocus.unfocus();
      if (isTrueOwner || (isMember && memberStatus == 'active')) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => GroupDetailScreen(group: g)),
        );
        // 🔥 THE FIX: Always reload the group list when returning!
        // This ensures if they were kicked, left, or the group changed, 
        // the UI is perfectly up-to-date instantly.
        if (mounted) _loadGroups();
      } else if (isMember && memberStatus == 'pending') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your request is still pending approval.'),
          ),
        );
      } else {
        _showGroupPreviewDialog(g);
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100, width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: handleAction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.indigo.shade400,
                            Colors.indigo.shade700,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.indigo.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : 'G',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
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
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      privacy == 'public'
                                          ? Icons.public
                                          : Icons.lock_outline,
                                      size: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      privacy.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey.shade700,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isTrueOwner) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: Colors.amber.shade200,
                                    ),
                                  ),
                                  child: Text(
                                    'OWNER',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber.shade800,
                                    ),
                                  ),
                                ),
                              ] else if (memberRole == 'admin') ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: Colors.blue.shade200,
                                    ),
                                  ),
                                  child: Text(
                                    'ADMIN',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade800,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (desc.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Text(
                    desc,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 18),
              ],
              Divider(height: 1, thickness: 1, color: Colors.grey.shade100),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isMember ? 'You are a member' : 'Public Community',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: buttonColor(),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      onPressed: _loading ? null : handleAction,
                      icon: Icon(buttonIcon(), size: 18),
                      label: Text(
                        buttonText(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGroupPreviewDialog(Map<String, dynamic> g) {
    final name = g['name'] ?? 'Unnamed Group';
    final desc = g['description'] ?? 'No description provided.';
    final privacy = g['privacy'] ?? 'public';
    final groupId = g['id'];

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.indigo.shade400, Colors.indigo.shade700],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.indigo.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'G',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          privacy == 'public' ? Icons.public : Icons.lock,
                          size: 14,
                          color: Colors.indigo.shade700,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          privacy.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FutureBuilder<List<dynamic>>(
                    future: _supabase
                        .from('group_members')
                        .select('id')
                        .eq('group_id', groupId)
                        .eq('status', 'active'),
                    builder: (context, snapshot) {
                      String countText = '...';
                      if (snapshot.hasData) {
                        countText = '${snapshot.data!.length} Members';
                      }
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.people_alt_rounded,
                              size: 14,
                              color: Colors.teal.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              countText,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal.shade700,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ABOUT THIS GROUP',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade500,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      desc,
                      style: TextStyle(
                        color: Colors.grey.shade800,
                        height: 1.4,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        if (privacy == 'public') {
                          _joinPublicGroup(groupId);
                        } else {
                          _joinByCodeDialog();
                        }
                      },
                      child: const Text(
                        'Join Group',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Determine which list to show based on the active tab
    final currentList = _selectedTab == 0 ? _myGroups : _discoverGroups;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Communities',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.key_rounded,
              color: Colors.indigo,
            ), // 🔥 Fixed Icon
            tooltip: 'Join by code',
            onPressed: _joinByCodeDialog,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(
            130,
          ), // Increased height to fit tabs
          child: Container(
            color: Colors.white,
            child: Column(
              children: [
                // Search Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (v) {
                      _searchFocus.unfocus();
                      _loadGroups(query: v);
                    },
                    decoration: InputDecoration(
                      hintText: 'Search communities...',
                      hintStyle: TextStyle(color: Colors.grey.shade500),
                      prefixIcon: Icon(
                        Icons.search,
                        color: Colors.grey.shade400,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      suffixIcon: IconButton(
                        icon: Icon(Icons.clear, color: Colors.grey.shade400),
                        onPressed: () {
                          _searchCtrl.clear();
                          _searchFocus.unfocus();
                          _loadGroups();
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                    ),
                  ),
                ),

                // 🔥 My Groups / Discover Toggle Tabs
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            _searchFocus.unfocus();
                            setState(() => _selectedTab = 0);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _selectedTab == 0
                                  ? Colors.white
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: _selectedTab == 0
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.05,
                                        ),
                                        blurRadius: 4,
                                      ),
                                    ]
                                  : [],
                            ),
                            child: Center(
                              child: Text(
                                'My Groups',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _selectedTab == 0
                                      ? Colors.indigo.shade700
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            _searchFocus.unfocus();
                            setState(() => _selectedTab = 1);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _selectedTab == 1
                                  ? Colors.white
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: _selectedTab == 1
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.05,
                                        ),
                                        blurRadius: 4,
                                      ),
                                    ]
                                  : [],
                            ),
                            child: Center(
                              child: Text(
                                'Discover',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _selectedTab == 1
                                      ? Colors.indigo.shade700
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: Colors.indigo,
        onRefresh: () async {
          _searchFocus.unfocus();
          _loadGroups(query: _searchCtrl.text);
        },
        child: _loading && currentList.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : currentList.isEmpty
            ? Center(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _selectedTab == 0
                            ? Icons.groups_rounded
                            : Icons.travel_explore_rounded,
                        size: 80,
                        color: Colors.indigo.shade100,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _selectedTab == 0
                            ? 'No groups joined yet'
                            : 'No new public groups',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _selectedTab == 0
                            ? 'Switch to Discover to find a community!'
                            : 'Check back later or create your own!',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.only(
                  top: 16,
                  left: 16,
                  right: 16,
                  bottom: 100,
                ),
                itemCount: currentList.length,
                itemBuilder: (_, i) => _buildGroupTile(currentList[i]),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.indigo.shade600,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: () async {
          _searchFocus.unfocus();
          final user = Supabase.instance.client.auth.currentUser;
          if (user == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('You must be logged in')),
            );
            return;
          }

          final res = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
          );

          if (res == true || res != null) {
            // Auto switch to My Groups to see the newly created group
            setState(() => _selectedTab = 0);
            _loadGroups();
          }
        },
        icon: const Icon(Icons.add),
        label: const Text(
          'Create',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }
}