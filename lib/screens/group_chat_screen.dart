import 'package:flutter/material.dart';
import '../services/group_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GroupChatScreen extends StatefulWidget {
  final dynamic groupId;
  final String groupName;

  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final GroupService _svc = GroupService();
  final _msgCtrl = TextEditingController();
  final _scrollController = ScrollController();
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _channel;

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _isNearBottom = true;

  List<Map<String, dynamic>> _messages = [];

  String? get _userId => _supabase.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _subscribeToMessages();
    _subscribeToActivity();

    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;

      if (_scrollController.position.pixels <= 120 &&
          !_loadingMore &&
          _hasMore &&
          !_loading) {
        _loadOlder();
      }

      final position = _scrollController.position;
      _isNearBottom = position.pixels >= (position.maxScrollExtent - 80);
    });

    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;

      final position = _scrollController.position;

      // 👇 THIS IS MORE RELIABLE
      _isNearBottom = position.pixels >= (position.maxScrollExtent - 80);
    });
  }

  Future<void> _loadInitial() async {
    setState(() => _loading = true);
    try {
      final data = await _svc.getLatestGroupMessages(widget.groupId);
      _messages = data;
      _hasMore = data.length == 30;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom(force: true);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadOlder() async {
    if (_messages.isEmpty) return;

    setState(() => _loadingMore = true);
    try {
      final oldest = _messages.first['created_at'];
      final oldestTime = DateTime.tryParse(oldest.toString());
      if (oldestTime == null) {
        _hasMore = false;
        return;
      }

      final older = await _svc.getOlderGroupMessages(
        widget.groupId,
        oldestTime,
      );

      if (older.isEmpty) {
        _hasMore = false;
      } else {
        final prevHeight = _scrollController.position.maxScrollExtent;

        setState(() {
          _messages = [...older, ..._messages];
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            final newHeight = _scrollController.position.maxScrollExtent;
            final diff = newHeight - prevHeight;
            _scrollController.jumpTo(_scrollController.offset + diff);
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  String _formatTime(dynamic raw) {
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return '';

    final dt = parsed.toLocal();

    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$min $ampm';
  }

  String _dayLabel(dynamic raw) {
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return '';

    final dt = parsed.toLocal();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(msgDay).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  void _subscribeToMessages() {
    _channel = _supabase.channel('group-chat-${widget.groupId}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'group_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'group_id',
          value: widget.groupId.toString(),
        ),
        // filter: 'group_id=eq.${widget.groupId}',
        callback: (payload) {
          final newMsg = payload.newRecord;
          final wasAtBottom = _isNearBottom;

          if (!mounted) return;

          setState(() {
            final index = _messages.indexWhere(
              (m) =>
                  m['message'] == newMsg['message'] &&
                  m['user_id'] == newMsg['user_id'] &&
                  m['is_sending'] == true,
            );

            if (index != -1) {
              // replace temp message
              _messages[index] = newMsg;
            } else {
              // avoid real duplicates
              final alreadyExists = _messages.any(
                (m) => m['id'] == newMsg['id'],
              );

              if (!alreadyExists) {
                _messages.add(newMsg);
              }
            }

            // 🔥 ALWAYS SORT
            _messages.sort(
              (a, b) => DateTime.parse(
                a['created_at'],
              ).compareTo(DateTime.parse(b['created_at'])),
            );
          });

          _scrollToBottom(force: wasAtBottom);
        },
      )
      ..subscribe();
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _userId == null) return;

    final name = await _svc.getMyDisplayName(_userId!);

    final tempMessage = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'group_id': widget.groupId,
      'user_id': _userId,
      'sender_name': name,
      'message': text,
      'created_at': DateTime.now().toIso8601String(),
      'is_sending': true,
    };

    setState(() {
      _messages.add(tempMessage);
    });

    _messages.sort(
      (a, b) => DateTime.parse(
        a['created_at'],
      ).compareTo(DateTime.parse(b['created_at'])),
    );

    _msgCtrl.clear();

    _scrollToBottom(force: true);

    await _svc.sendGroupMessage(
      groupId: widget.groupId,
      senderUserId: _userId!,
      senderName: name,
      message: text,
    );

    if (!mounted) return;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.indigo.shade700,
              Colors.indigo.shade50,
              Colors.white,
            ],
            stops: const [0.0, 0.18, 0.55],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : Stack(
                        children: [
                          ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                            itemCount: _messages.length,
                            itemBuilder: (_, i) {
                              final m = _messages[i];
                              final isActivity = m['type'] == 'activity';
                              final isMe = m['user_id']?.toString() == _userId;
                              final isSending = m['is_sending'] == true;
                              final isError = m['is_error'] == true;

                              final prevDay = i > 0
                                  ? _dayLabel(_messages[i - 1]['created_at'])
                                  : null;
                              final currentDay = _dayLabel(m['created_at']);
                              final showSeparator =
                                  i == 0 || prevDay != currentDay;

                              return Column(
                                children: [
                                  if (showSeparator)
                                    _buildDaySeparator(currentDay),

                                  if (isActivity)
                                    _buildActivityBubble(m)
                                  else
                                    _buildMessageBubble(
                                      message: m,
                                      isMe: isMe,
                                      isSending: isSending,
                                      isError: isError,
                                    ),
                                ],
                              );
                            },
                          ),
                          if (_loadingMore)
                            const Positioned(
                              top: 8,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              _buildComposer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            blurRadius: 20,
            offset: const Offset(0, 8),
            color: Colors.black.withValues(alpha: 0.12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.indigo.shade300, Colors.indigo.shade600],
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                widget.groupName.isNotEmpty
                    ? widget.groupName[0].toUpperCase()
                    : 'G',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.groupName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Group chat',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _loadInitial,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildDaySeparator(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble({
    required Map<String, dynamic> message,
    required bool isMe,
    required bool isSending,
    required bool isError,
  }) {
    final name = (message['sender_name'] ?? 'User').toString();
    final text = (message['message'] ?? '').toString();
    final time = _formatTime(message['created_at']);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Row(
          mainAxisAlignment: isMe
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe) _avatar(name),
            if (!isMe) const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: isMe
                      ? LinearGradient(
                          colors: [
                            Colors.indigo.shade500,
                            Colors.indigo.shade700,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: isMe ? null : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMe ? 18 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ],
                  border: isMe ? null : Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isMe)
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    if (!isMe) const SizedBox(height: 4),
                    Text(
                      text,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.35,
                        color: isMe ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 11,
                            color: isMe
                                ? Colors.white.withValues(alpha: 0.75)
                                : Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isSending)
                          const SizedBox(
                            width: 11,
                            height: 11,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        if (isError)
                          const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 14,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (isMe) const SizedBox(width: 8),
            if (isMe) _avatar(name),
          ],
        ),
      ),
    );
  }

  Widget _avatar(String name) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'U';
    return CircleAvatar(
      radius: 16,
      backgroundColor: Colors.indigo.shade200,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            blurRadius: 24,
            offset: const Offset(0, -6),
            color: Colors.black.withValues(alpha: 0.06),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: TextField(
                  controller: _msgCtrl,
                  maxLines: 5,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Write a message...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.indigo.shade500, Colors.indigo.shade700],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _activitySubscribed = false;

  void _subscribeToActivity() {
    if (_activitySubscribed) return;
    _activitySubscribed = true;

    _supabase
        .channel('public:group_activity') // ✅ FIXED
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'group_activity',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: widget.groupId.toString(), // ✅ STRING FIX
          ),
          callback: (payload) {
            debugPrint("🔥 ACTIVITY REALTIME: ${payload.newRecord}");
            final wasAtBottom = _isNearBottom;

            final a = payload.newRecord;

            if (!mounted) return;

            final activityMsg = {
              'id': 'activity_${a['id']}',
              'type': 'activity',
              'message': a['title'] ?? '',
              'sub': a['body'],
              'xp': a['xp_earned'] ?? 0,
              'created_at': a['created_at'],
            };

            setState(() {
              final exists = _messages.any((m) => m['id'] == activityMsg['id']);

              if (!exists) {
                _messages.add(activityMsg);
              }

              _messages.sort(
                (a, b) => DateTime.parse(
                  a['created_at'],
                ).compareTo(DateTime.parse(b['created_at'])),
              );
            });
            _scrollToBottom(force: wasAtBottom);
          },
        )
        .subscribe();
  }

  Widget _buildActivityBubble(Map<String, dynamic> m) {
    final text = m['message'] ?? '';
    final sub = m['sub'] ?? '';
    final xp = m['xp'] ?? 0;
    final time = _formatTime(m['created_at']);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.indigo.shade100),
          ),
          child: Column(
            children: [
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (sub != null && sub.toString().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  sub,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
              if (xp > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '+$xp XP',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                time,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      if (force) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      } else {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollController.dispose();
    _channel?.unsubscribe(); // 👈 MUST
    super.dispose();
  }
}
