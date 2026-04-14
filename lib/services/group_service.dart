import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GroupService {
  final SupabaseClient supabase = Supabase.instance.client;

  /// 🔥 CREATE GROUP
  Future<Map<String, dynamic>?> createGroup({
    required String name,
    String? description,
    required String ownerId,
    String privacy = 'private',
    String joinMode = 'code',
    String? inviteCode,
    bool isLocked = false,
  }) async {
    try {
      final data = await supabase
          .from('groups')
          .insert({
            'name': name,
            'description': description ?? '',
            'owner_id': ownerId,
            'privacy': privacy,
            'join_mode': joinMode,
            'join_code': inviteCode,
            'is_locked': isLocked,
          })
          .select()
          .single();

      return data;
    } catch (e) {
      debugPrint('❌ Create group error: $e');
      return null;
    }
  }

  /// 🔥 CREATE MEMBERSHIP
  Future<void> createMembership({
    required dynamic groupId,
    required String userId,
    String role = 'member',
    String status = 'active',
  }) async {
    try {
      await supabase.from('group_members').insert({
        'group_id': groupId,
        'user_id': userId,
        'role': role,
        'status': status,
      });
    } catch (e) {
      debugPrint('❌ Create membership error: $e');
      rethrow;
    }
  }

  /// 🔥 FIND GROUP BY CODE
  Future<Map<String, dynamic>?> findGroupByInviteCode(String code) async {
    try {
      final data = await supabase
          .from('groups')
          .select()
          .eq(
            'invite_code',
            code,
          ) // Make sure your groups table actually uses 'join_code' or 'invite_code'
          .maybeSingle();

      return data;
    } catch (e) {
      debugPrint('❌ Find group error: $e');
      return null;
    }
  }

  /// 🔥 JOIN GROUP (SMART LOGIC WITH ACTIVITY LOG)
  Future<void> joinGroupByCode({
    required dynamic groupId,
    required String userId,
    required String privacy,
  }) async {
    try {
      final existing = await supabase
          .from('group_members')
          .select()
          .eq('group_id', groupId)
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        debugPrint('⚠️ Already a member');
        return;
      }

      await supabase.from('group_members').insert({
        'group_id': groupId,
        'user_id': userId,
        'role': 'member',
        'status': privacy == 'public' ? 'active' : 'pending',
      });

      // 🔥 LOG ACTIVITY IF PUBLIC JOIN
      if (privacy == 'public') {
        final userName = await getMyDisplayName(userId);
        await addGroupActivity(
          groupId: groupId,
          actorUserId: userId,
          actorName: userName,
          activityType: 'joined',
          title: '$userName joined the group',
        );
      }
    } catch (e) {
      debugPrint('❌ Join group error: $e');
      rethrow;
    }
  }

  /// 🔥 GET USER GROUPS
  Future<List<Map<String, dynamic>>> getUserGroups(String userId) async {
    try {
      final data = await supabase
          .from('group_members')
          .select('group_id, role, status')
          .eq('user_id', userId)
          .eq('status', 'active');

      return (data as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('❌ Fetch user groups error: $e');
      return [];
    }
  }

  /// 🔥 GET ALL MEMBERS OF A GROUP
  Future<List<Map<String, dynamic>>> getGroupMembers(dynamic groupId) async {
    try {
      final res = await supabase
          .from('group_members')
          .select('id, user_id, role, status')
          .eq('group_id', groupId);

      return (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('❌ Fetch members error: $e');
      return [];
    }
  }

  /// 🔥 APPROVE USER (WITH ACTIVITY LOG)
  Future<void> approveUser(String memberId) async {
    // 1. Fetch member details before updating so we know who it is
    final member = await supabase
        .from('group_members')
        .select('group_id, user_id')
        .eq('id', memberId)
        .maybeSingle();

    // 2. Approve them
    await supabase
        .from('group_members')
        .update({'status': 'active'})
        .eq('id', memberId);

    // 3. Log it
    if (member != null) {
      final userName = await getMyDisplayName(member['user_id']);
      await addGroupActivity(
        groupId: member['group_id'],
        actorUserId: member['user_id'],
        actorName: userName,
        activityType: 'joined',
        title: '$userName joined the group',
      );
    }
  }

  /// 🔥 REJECT USER
  Future<void> rejectUser(String memberId) async {
    await supabase.from('group_members').delete().eq('id', memberId);
  }

  /// 🔥 PROMOTE TO ADMIN (WITH ACTIVITY LOG)
  Future<void> promoteToAdmin(String memberId) async {
    final member = await supabase
        .from('group_members')
        .select('group_id, user_id')
        .eq('id', memberId)
        .maybeSingle();

    await supabase
        .from('group_members')
        .update({'role': 'admin'})
        .eq('id', memberId);

    if (member != null) {
      final userName = await getMyDisplayName(member['user_id']);
      await addGroupActivity(
        groupId: member['group_id'],
        actorUserId: member['user_id'],
        actorName: userName,
        activityType: 'promoted',
        title: '$userName was promoted to Admin',
      );
    }
  }

  /// 🔥 DEMOTE FROM ADMIN TO MEMBER (WITH ACTIVITY LOG)
  Future<void> demoteFromAdmin(String memberId) async {
    final member = await supabase
        .from('group_members')
        .select('group_id, user_id')
        .eq('id', memberId)
        .maybeSingle();

    await supabase
        .from('group_members')
        .update({'role': 'member'})
        .eq('id', memberId);

    if (member != null) {
      final userName = await getMyDisplayName(member['user_id']);
      await addGroupActivity(
        groupId: member['group_id'],
        actorUserId: member['user_id'],
        actorName: userName,
        activityType: 'demoted',
        title: '$userName was demoted to Member',
      );
    }
  }

  /// 🔥 REMOVE MEMBER (WITH ACTIVITY LOG)
  Future<void> removeMember(String memberId) async {
    final member = await supabase
        .from('group_members')
        .select('group_id, user_id')
        .eq('id', memberId)
        .maybeSingle();

    if (member != null) {
      final userName = await getMyDisplayName(member['user_id']);
      await addGroupActivity(
        groupId: member['group_id'],
        actorUserId: member['user_id'],
        actorName: userName,
        activityType: 'left',
        title: '$userName was removed from the group',
      );
    }

    await supabase.from('group_members').delete().eq('id', memberId);
  }

  /// 🔥 GET LEADERBOARD
  Future<List<Map<String, dynamic>>> getLeaderboard(dynamic groupId) async {
    try {
      final res = await supabase
          .from('group_members')
          .select('user_id, role, status, total_xp')
          .eq('group_id', groupId)
          .order('total_xp', ascending: false);

      return (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('❌ Leaderboard error: $e');
      return [];
    }
  }

  Future<void> leaveGroup(dynamic userId, dynamic groupId) async {
    try {
      final myName = await getMyDisplayName(userId!);

      await supabase
          .from('group_members')
          .delete()
          .eq('group_id', groupId)
          .eq('user_id', userId!);

      // 🔥 Log the leave activity
      await addGroupActivity(
        groupId: groupId,
        actorUserId: userId!,
        actorName: myName,
        activityType: 'left',
        title: '$myName left the group',
      );
    } catch (e) {
      debugPrint('Leave error: $e');
    }
  }

  /// 🔥 ABANDON GROUP & TRANSFER OWNERSHIP (WITH ACTIVITY LOG)
  Future<void> abandonGroup(dynamic groupId, String currentOwnerId) async {
    try {
      final res = await supabase
          .from('group_members')
          .select('id, user_id, total_xp')
          .eq('group_id', groupId)
          .eq('status', 'active')
          .neq('user_id', currentOwnerId)
          .order('total_xp', ascending: false);

      final otherMembers = (res as List).cast<Map<String, dynamic>>();
      debugPrint('Other Members: $otherMembers');
      debugPrint('Curr Members: $currentOwnerId');

      if (otherMembers.isEmpty) {
        // If no one is left, delete the group entirely.
        await supabase.from('groups').delete().eq('id', groupId).select();
        debugPrint("Group deleted successfully because no members were left.");
      } else {
        final nextOwnerId = otherMembers.first['user_id'];
        final nextOwnerMemberId = otherMembers.first['id'];

        // 🔥 FIX 1: Add .select() to stop silent failures
        await supabase
            .from('groups')
            .update({'owner_id': nextOwnerId})
            .eq('id', groupId)
            .select();

        // Elevate the new owner in the group_members table
        await supabase
            .from('group_members')
            .update({'role': 'owner'})
            .eq('id', nextOwnerMemberId)
            .select(); // 🔥 Added .select()

        final currentOwnerName = await getMyDisplayName(currentOwnerId);
        final nextOwnerName = await getMyDisplayName(nextOwnerId);

        // Log the transfer
        await addGroupActivity(
          groupId: groupId,
          actorUserId: currentOwnerId,
          actorName: currentOwnerName,
          activityType: 'promoted',
          title: '$nextOwnerName is the new Owner',
          body: '$currentOwnerName left the group and transferred ownership.',
        );

        // 🔥 FIX 2: NOW it is safe to leave the group, because we've already transferred power!
        await leaveGroup(currentOwnerId, groupId);
      }
    } catch (e) {
      debugPrint('❌ Abandon group error: $e');
      rethrow;
    } finally {
      debugPrint('✅ Group Abandon Sequence Finished');
    }
  }

  /// 🔥 UPDATE XP IN GROUP
  Future<void> addXPToUser({
    required dynamic groupId,
    required String userId,
    required int xp,
  }) async {
    try {
      final row = await supabase
          .from('group_members')
          .select('total_xp')
          .eq('group_id', groupId)
          .eq('user_id', userId)
          .maybeSingle();

      if (row == null) return;

      final currentXP = (row['total_xp'] ?? 0) as int;
      final newXP = currentXP + xp;

      await supabase
          .from('group_members')
          .update({'total_xp': newXP})
          .eq('group_id', groupId)
          .eq('user_id', userId);
    } catch (e) {
      debugPrint("❌ XP update error: $e");
    }
  }

  Future<String> getMyDisplayName(String userId) async {
    try {
      final res = await supabase
          .from('profiles')
          .select('full_name')
          .eq('id', userId)
          .maybeSingle();

      final name = res?['full_name']?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
    } catch (_) {}
    return 'User';
  }

  Future<int?> getUserRank(dynamic groupId, String userId) async {
    try {
      final res = await supabase
          .from('group_members')
          .select('user_id, total_xp')
          .eq('group_id', groupId)
          .order('total_xp', ascending: false);

      final rows = (res as List).cast<Map<String, dynamic>>();
      final index = rows.indexWhere((r) => r['user_id'].toString() == userId);
      if (index == -1) return null;
      return index + 1;
    } catch (e) {
      debugPrint('❌ Rank error: $e');
      return null;
    }
  }

  Future<void> addGroupActivity({
    required dynamic groupId,
    required String actorUserId,
    required String actorName,
    required String activityType,
    required String title,
    double value = 0,
    String? body,
    int xpEarned = 0,
    int? oldRank,
    int? newRank,
    String? habitId,
  }) async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      final response = await supabase.from('group_activity').insert({
        'group_id': groupId,
        'user_id': currentUser
            .id, // 🔥 FIX 1: This is the Admin/Owner pressing the button
        'xp': xpEarned,
        'actor_user_id':
            actorUserId, // 🔥 This is the user the activity is ABOUT
        'actor_name': actorName,
        'activity_type': activityType,
        'title': title,
        'body': body,
        'xp_earned': xpEarned,
        'old_rank': oldRank,
        'new_rank': newRank,
        'value': value,
        'habit_id': habitId,
      }).select();

      debugPrint('✅ Activity successfully logged: $response');
    } catch (e) {
      debugPrint('❌ Activity log error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getGroupActivity(dynamic groupId) async {
    try {
      final res = await supabase
          .from('group_activity')
          .select()
          .eq('group_id', groupId)
          .order('created_at', ascending: false);

      return (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('❌ Fetch activity error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> sendGroupMessage({
    required dynamic groupId,
    required String senderUserId,
    required String senderName,
    required String message,
  }) async {
    try {
      await supabase
          .from('group_messages')
          .insert({
            'group_id': groupId,
            'user_id': senderUserId,
            'sender_name': senderName,
            'message': message,
          })
          .select()
          .single();
    } catch (e) {
      debugPrint('❌ Send message error: $e');
      return null;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getLatestGroupMessages(
    dynamic groupId,
  ) async {
    try {
      final res = await supabase
          .from('group_messages')
          .select('id, group_id, user_id, sender_name, message, created_at')
          .eq('group_id', groupId)
          .order('created_at', ascending: false)
          .limit(30);

      final rows = (res as List).cast<Map<String, dynamic>>();
      return rows.reversed.toList();
    } catch (e) {
      debugPrint('❌ Fetch latest messages error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getOlderGroupMessages(
    dynamic groupId,
    DateTime before,
  ) async {
    try {
      final res = await supabase
          .from('group_messages')
          .select('id, group_id, user_id, sender_name, message, created_at')
          .eq('group_id', groupId)
          .lt('created_at', before.toIso8601String())
          .order('created_at', ascending: false)
          .limit(30);

      final rows = (res as List).cast<Map<String, dynamic>>();
      return rows.reversed.toList();
    } catch (e) {
      debugPrint('❌ Fetch older messages error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getGroupMessages(dynamic groupId) async {
    try {
      final res = await supabase
          .from('group_messages')
          .select()
          .eq('group_id', groupId)
          .order('created_at', ascending: true);

      return (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('❌ Fetch messages error: $e');
      return [];
    }
  }
}
