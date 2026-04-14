import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Clipboard
import '../services/group_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GroupAdminScreen extends StatefulWidget {
  final dynamic groupId;

  const GroupAdminScreen({super.key, required this.groupId});

  @override
  State<GroupAdminScreen> createState() => _GroupAdminScreenState();
}

class _GroupAdminScreenState extends State<GroupAdminScreen> {
  final GroupService _svc = GroupService();
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  String? _joinCode;
  String? _ownerId;
  
  // 🔥 Track the reset interval state
  String _resetInterval = 'weekly';

  String? get _myUserId => _supabase.auth.currentUser?.id;

  List<Map<String, dynamic>> activeMembers = [];
  List<Map<String, dynamic>> pendingMembers = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      // 1. Fetch Group Info (added reset_interval to the select)
      final groupData = await _supabase
          .from('groups')
          .select('join_code, owner_id, reset_interval')
          .eq('id', widget.groupId)
          .maybeSingle();

      _joinCode = groupData?['join_code']?.toString();
      _ownerId = groupData?['owner_id']?.toString();
      
      // Grab the current setting, defaulting to weekly
      _resetInterval = groupData?['reset_interval']?.toString() ?? 'weekly'; 

      // 2. Fetch Members
      final data = await _svc.getGroupMembers(widget.groupId);

      // 3. Enrich members with display names
      final enriched = <Map<String, dynamic>>[];
      for (final row in data) {
        final userId = row['user_id']?.toString();
        String displayName = 'Unknown User';

        if (userId != null) {
          final profile = await _supabase
              .from('profiles')
              .select('full_name')
              .eq('id', userId)
              .maybeSingle();

          if (profile != null && profile['full_name'] != null) {
            displayName = profile['full_name'].toString();
          }
        }
        enriched.add({...row, 'display_name': displayName});
      }

      setState(() {
        activeMembers = enriched.where((m) => m['status'] == 'active').toList();
        pendingMembers = enriched.where((m) => m['status'] == 'pending').toList();
      });
    } catch (e) {
      debugPrint('Admin load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copyInviteCode() {
    if (_joinCode != null) {
      Clipboard.setData(ClipboardData(text: _joinCode!));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Invite code copied to clipboard!'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String content,
    required String confirmText,
    required Color confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(content, style: const TextStyle(fontSize: 16, height: 1.4)),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Manage Group', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                children: [
                  if (_joinCode != null) _buildInviteCodeCard(),
                  const SizedBox(height: 24),

                  // 🔥 INJECTED SETTINGS CARD HERE
                  _buildResetIntervalCard(),
                  const SizedBox(height: 24),

                  if (pendingMembers.isNotEmpty) ...[
                    _buildSectionHeader("Pending Requests", Icons.person_add_alt_1, Colors.orange),
                    const SizedBox(height: 12),
                    ...pendingMembers.map((m) => _buildMemberTile(m, isPending: true)),
                    const SizedBox(height: 24),
                  ],

                  _buildSectionHeader("Active Members", Icons.group, Colors.indigo),
                  const SizedBox(height: 12),
                  if (activeMembers.isEmpty)
                    const Center(child: Text("No active members found.")),
                  ...activeMembers.map((m) => _buildMemberTile(m)),
                ],
              ),
            ),
    );
  }

  Widget _buildInviteCodeCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade500, Colors.indigo.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Group Invite Code",
            style: TextStyle(color: Colors.indigo.shade100, fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _joinCode!,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28, letterSpacing: 2.0),
              ),
              InkWell(
                onTap: _copyInviteCode,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.copy, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 🔥 NEW: The Leaderboard Reset Settings Card
  Widget _buildResetIntervalCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.update_rounded, color: Colors.indigo.shade600),
              const SizedBox(width: 8),
              const Text("Leaderboard Reset", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.black87)),
            ],
          ),
          const SizedBox(height: 8),
          Text("When should the group leaderboard clear?", style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _resetInterval,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            items: const [
              DropdownMenuItem(value: 'daily', child: Text('Daily (Midnight)')),
              DropdownMenuItem(value: 'weekly', child: Text('Weekly (Sunday Night)')),
              DropdownMenuItem(value: 'monthly', child: Text('Monthly (1st of Month)')),
              DropdownMenuItem(value: 'yearly', child: Text('Yearly (Jan 1st)')),
            ],
            onChanged: (val) async {
              if (val == null) return;
              setState(() => _resetInterval = val);
              
              try {
                await _supabase
                    .from('groups')
                    .update({'reset_interval': val})
                    .eq('id', widget.groupId);
                    
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Leaderboard will now reset $val.'), backgroundColor: Colors.green.shade600),
                  );
                }
              } catch (e) {
                debugPrint("Failed to update reset interval: $e");
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
        ),
      ],
    );
  }

  Widget _buildMemberTile(Map<String, dynamic> m, {bool isPending = false}) {
    final id = m['id'];
    final userId = m['user_id']?.toString();
    final role = m['role']?.toString().toLowerCase() ?? 'member';
    final name = m['display_name']?.toString() ?? 'User';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    final isAdmin = role == 'admin' || role == 'owner';
    final isOwner = userId == _ownerId;
    final isMe = userId == _myUserId;

    // Determine the label text
    String labelText = role.toUpperCase();
    if (isOwner) labelText = 'OWNER';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isMe ? Colors.indigo.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isMe ? Colors.indigo.shade100 : Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: isAdmin ? Colors.amber.shade100 : Colors.indigo.shade100,
          foregroundColor: isAdmin ? Colors.amber.shade800 : Colors.indigo.shade800,
          child: Text(initial, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ),
        title: Text(
          isMe ? "$name (You)" : name,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isAdmin ? Colors.amber.shade50 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: isAdmin ? Colors.amber.shade200 : Colors.grey.shade300),
                ),
                child: Text(
                  labelText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isAdmin ? Colors.amber.shade700 : Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // TRAILING LOGIC:
        trailing: isPending
            ? _buildPendingActions(id.toString())
            : (isMe || isOwner) 
                // Don't allow modifying the owner, and don't allow removing yourself from this menu!
                ? const SizedBox.shrink() 
                : _buildActiveMemberActions(id.toString(), name, role),
      ),
    );
  }

  Widget _buildPendingActions(String memberId) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: CircleAvatar(
            backgroundColor: Colors.red.shade50,
            radius: 18,
            child: const Icon(Icons.close, color: Colors.red, size: 20),
          ),
          onPressed: () async {
            try {
              await _svc.rejectUser(memberId);
              if (!mounted) return;
              await _loadData();
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
            }
          },
        ),
        IconButton(
          icon: CircleAvatar(
            backgroundColor: Colors.green.shade50,
            radius: 18,
            child: const Icon(Icons.check, color: Colors.green, size: 20),
          ),
          onPressed: () async {
            try {
              await _svc.approveUser(memberId);
              if (!mounted) return;
              await _loadData();
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
            }
          },
        ),
      ],
    );
  }

  Widget _buildActiveMemberActions(String memberId, String name, String currentRole) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) async {
        try {
          if (value == 'promote') {
            final confirm = await _showConfirmDialog(
              title: 'Promote User',
              content: 'Are you sure you want to promote $name to Admin?',
              confirmText: 'Promote',
              confirmColor: Colors.amber.shade700,
            );
            if (!confirm) return;

            await _svc.promoteToAdmin(memberId);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Promoted to Admin'), backgroundColor: Colors.green));

          } else if (value == 'demote') {
             final confirm = await _showConfirmDialog(
              title: 'Demote Admin',
              content: 'Are you sure you want to demote $name to a regular member?',
              confirmText: 'Demote',
              confirmColor: Colors.orange.shade700,
            );
            if (!confirm) return;

            await _svc.demoteFromAdmin(memberId);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Demoted to Member'), backgroundColor: Colors.orange));

          } else if (value == 'remove') {
            final confirm = await _showConfirmDialog(
              title: 'Remove User',
              content: 'Are you sure you want to completely remove $name from the group?',
              confirmText: 'Remove',
              confirmColor: Colors.red.shade600,
            );
            if (!confirm) return;

            await _svc.removeMember(memberId);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Member removed'), backgroundColor: Colors.red));
          }
          await _loadData();
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action failed: $e'), backgroundColor: Colors.red));
        }
      },
      itemBuilder: (context) => [
        if (currentRole == 'member')
          const PopupMenuItem(
            value: 'promote',
            child: Row(
              children: [
                Icon(Icons.shield, color: Colors.amber, size: 20),
                SizedBox(width: 12),
                Text('Promote to Admin'),
              ],
            ),
          ),
        if (currentRole == 'admin')
          const PopupMenuItem(
            value: 'demote',
            child: Row(
              children: [
                Icon(Icons.keyboard_arrow_down, color: Colors.orange, size: 20),
                SizedBox(width: 12),
                Text('Demote to Member'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'remove',
          child: Row(
            children: [
              Icon(Icons.person_remove, color: Colors.red, size: 20),
              SizedBox(width: 12),
              Text('Remove Member', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }
}