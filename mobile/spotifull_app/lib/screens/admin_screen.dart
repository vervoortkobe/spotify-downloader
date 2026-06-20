import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotifull_app/providers/admin_provider.dart';
import 'package:spotifull_app/screens/home_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminProvider>().loadUsers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF07110b),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Admin Panel',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _statCard('Total Users', '${admin.users.length}', Icons.people),
                const SizedBox(width: 12),
                _statCard(
                  'Active Now',
                  '${admin.activeUserCount}',
                  Icons.person_pin,
                ),
                const SizedBox(width: 12),
                _statCard(
                  'Pending',
                  '${admin.pendingApprovalCount}',
                  Icons.hourglass_empty,
                ),
              ],
            ),
          ),
          Expanded(
            child: admin.isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF10b981)),
                  )
                : ListView.builder(
                    itemCount: admin.users.length,
                    itemBuilder: (_, i) {
                      final u = admin.users[i];
                      return Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0f1d17),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundImage: u.photoUrl.isNotEmpty
                                  ? NetworkImage(u.photoUrl)
                                  : null,
                              backgroundColor: const Color(0xFF1a3a2a),
                              radius: 20,
                              child: u.photoUrl.isEmpty
                                  ? Text(u.displayName[0].toUpperCase())
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    u.displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    u.email,
                                    style: const TextStyle(
                                      color: Color(0xFFa1a1aa),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!u.isApproved)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.check_circle,
                                      color: Color(0xFF10b981),
                                    ),
                                    onPressed: () => admin.approveUser(u.uid),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.cancel,
                                      color: Color(0xFFef4444),
                                    ),
                                    onPressed: () => admin.denyUser(u.uid),
                                  ),
                                ],
                              ),
                            if (u.isAdmin)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF10b981,
                                  ).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Admin',
                                  style: TextStyle(
                                    color: Color(0xFF10b981),
                                    fontSize: 11,
                                  ),
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

  Widget _statCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0f1d17),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1a3a2a)),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF10b981), size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Color(0xFFa1a1aa), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
