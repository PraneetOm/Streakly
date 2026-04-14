import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/group_service.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  
  bool _isPrivate = true;
  String _joinMode = 'code';
  final bool _isLocked = false; // Kept your variable
  
  final GroupService _svc = GroupService();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String _generateInviteCode() {
    final id = DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
    return id.substring(id.length - 6);
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus(); // Drop keyboard

    setState(() => _saving = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception("User not logged in");

      final inviteCode = _joinMode == 'code' && _isPrivate ? _generateInviteCode() : null;

      final res = await _svc.createGroup(
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        ownerId: user.id,
        privacy: _isPrivate ? 'private' : 'public',
        joinMode: _isPrivate ? _joinMode : 'open',
        inviteCode: inviteCode,
        isLocked: _isLocked,
      );

      if (res == null) throw Exception("Group creation failed on server.");

      final groupId = res['id'];

      await _svc.createMembership(
        groupId: groupId,
        userId: user.id,
        role: 'owner',
        status: 'active',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group created successfully!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, res); // Pass result back to refresh list
      }
    } catch (e) {
      debugPrint("❌ ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Create Community', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black87, letterSpacing: -0.5)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- GROUP DETAILS CARD ---
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(
                          'GROUP DETAILS',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 1.2),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
                          border: Border.all(color: Colors.grey.shade100, width: 1.5),
                        ),
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _nameCtrl,
                              textCapitalization: TextCapitalization.words,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                              decoration: InputDecoration(
                                labelText: 'Group Name',
                                labelStyle: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.normal),
                                prefixIcon: Icon(Icons.groups_rounded, color: Colors.indigo.shade400),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a group name' : null,
                            ),
                            Divider(height: 1, thickness: 1, color: Colors.grey.shade100),
                            TextFormField(
                              controller: _descCtrl,
                              textCapitalization: TextCapitalization.sentences,
                              minLines: 3,
                              maxLines: 5,
                              style: const TextStyle(fontSize: 15),
                              decoration: InputDecoration(
                                labelText: 'Description (Optional)',
                                alignLabelWithHint: true,
                                labelStyle: TextStyle(color: Colors.grey.shade500),
                                prefixIcon: Padding(
                                  padding: const EdgeInsets.only(bottom: 40), // Align icon to top of multiline
                                  child: Icon(Icons.description_outlined, color: Colors.indigo.shade400),
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 32),

                      // --- PRIVACY & ACCESS CARD ---
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(
                          'PRIVACY & ACCESS',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 1.2),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
                          border: Border.all(color: Colors.grey.shade100, width: 1.5),
                        ),
                        child: Column(
                          children: [
                            SwitchListTile(
                              value: _isPrivate,
                              activeThumbColor: Colors.indigo,
                              activeTrackColor: Colors.indigo.shade100,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              secondary: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: _isPrivate ? Colors.indigo.shade50 : Colors.green.shade50, shape: BoxShape.circle),
                                child: Icon(
                                  _isPrivate ? Icons.lock_rounded : Icons.public_rounded,
                                  color: _isPrivate ? Colors.indigo : Colors.green,
                                ),
                              ),
                              title: Text('Private Group', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                              subtitle: Text(
                                _isPrivate ? 'Only approved members can join' : 'Anyone can search and join',
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                              ),
                              onChanged: (v) => setState(() => _isPrivate = v),
                            ),
                            
                            // Animated Join Mode Dropdown (Only shows if Private)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              height: _isPrivate ? 80 : 0, // Hides smoothly if public
                              curve: Curves.easeInOut,
                              child: SingleChildScrollView(
                                physics: const NeverScrollableScrollPhysics(),
                                child: Column(
                                  children: [
                                    Divider(height: 1, thickness: 1, color: Colors.grey.shade100),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                      child: DropdownButtonFormField<String>(
                                        initialValue: _joinMode,
                                        icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade600),
                                        decoration: InputDecoration(
                                          labelText: 'Joining Method',
                                          labelStyle: TextStyle(color: Colors.grey.shade500),
                                          border: InputBorder.none,
                                        ),
                                        items: [
                                          DropdownMenuItem(
                                            value: 'code',
                                            child: Text('Invite Code (Auto-Approve)', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
                                          ),
                                          DropdownMenuItem(
                                            value: 'invite',
                                            child: Text('Request Only (Admin Approval)', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
                                          ),
                                        ],
                                        onChanged: (v) => setState(() => _joinMode = v ?? 'code'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // --- BOTTOM CREATE BUTTON ---
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, -5))],
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
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _saving ? null : _createGroup,
                    child: _saving
                        ? const SizedBox(
                            height: 24, 
                            width: 24, 
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)
                          )
                        : const Text('Create Group', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
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