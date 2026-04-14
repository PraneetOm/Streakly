import 'package:flutter/material.dart';
import '../services/group_service.dart';

class GroupActivityScreen extends StatefulWidget {
  final dynamic groupId;
  final String groupName;

  const GroupActivityScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupActivityScreen> createState() => _GroupActivityScreenState();
}

class _GroupActivityScreenState extends State<GroupActivityScreen> {
  final GroupService _svc = GroupService();
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _items = await _svc.getGroupActivity(widget.groupId);
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.groupName} Activity'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final item = _items[i];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          (item['actor_name'] ?? 'U').toString().substring(0, 1),
                        ),
                      ),
                      title: Text(item['title'] ?? ''),
                      subtitle: Text(item['body'] ?? ''),
                      trailing: item['xp_earned'] != null && item['xp_earned'] > 0
                          ? Text('+${item['xp_earned']} XP')
                          : null,
                    ),
                  );
                },
              ),
            ),
    );
  }
}