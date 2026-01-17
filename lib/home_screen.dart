import 'package:flutter/material.dart';
import 'services/user_storage_service.dart';
import 'camera_screen.dart';
import 'enroll_screen.dart';
import 'user_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final UserStorageService _storage = UserStorageService();
  int _userCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    debugPrint('🏠 HomeScreen: initState called');
    _loadUserCount();
  }

  Future<void> _loadUserCount() async {
    debugPrint('🏠 HomeScreen: Loading user count...');
    try {
      final count = await _storage.getUserCount();
      setState(() {
        _userCount = count;
        _isLoading = false;
      });
      debugPrint('🏠 HomeScreen: User count loaded: $_userCount');
    } catch (e) {
      debugPrint('❌ HomeScreen: Error loading user count: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _navigateToVerify() {
    debugPrint('🏠 HomeScreen: Navigating to verification screen');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CameraScreen(mode: CameraMode.verify),
      ),
    ).then((_) {
      debugPrint('🏠 HomeScreen: Returned from verification screen');
      _loadUserCount();
    });
  }

  void _navigateToEnroll() {
    debugPrint('🏠 HomeScreen: Navigating to enrollment screen');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const EnrollScreen()),
    ).then((_) {
      debugPrint('🏠 HomeScreen: Returned from enrollment screen');
      _loadUserCount();
    });
  }

  void _navigateToUserList() {
    debugPrint('🏠 HomeScreen: Navigating to user list screen');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const UserListScreen()),
    ).then((_) {
      debugPrint('🏠 HomeScreen: Returned from user list screen');
      _loadUserCount();
    });
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      '🏠 HomeScreen: Building UI - userCount: $_userCount, isLoading: $_isLoading',
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.blue))
            : Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    _buildHeader(),
                    const SizedBox(height: 40),

                    // User count badge
                    _buildUserCountBadge(),
                    const SizedBox(height: 40),

                    // Action cards
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildActionCard(
                            icon: Icons.verified_user,
                            title: 'Verify Face',
                            subtitle: 'Unlock the door',
                            color: Colors.blue,
                            onTap: _navigateToVerify,
                          ),
                          const SizedBox(height: 20),
                          _buildActionCard(
                            icon: Icons.person_add,
                            title: 'Enroll New User',
                            subtitle: 'Register a new face',
                            color: Colors.green,
                            onTap: _navigateToEnroll,
                          ),
                          const SizedBox(height: 20),
                          _buildActionCard(
                            icon: Icons.people,
                            title: 'View Enrolled Users',
                            subtitle:
                                '$_userCount ${_userCount == 1 ? 'user' : 'users'} enrolled',
                            color: Colors.orange,
                            onTap: _navigateToUserList,
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

  Widget _buildHeader() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.security, color: Colors.blue, size: 32),
            ),
            const SizedBox(width: 16),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Godrej Advantis IoT9',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  'Smart Digital Lock',
                  style: TextStyle(
                    color: Colors.blue,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUserCountBadge() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.blue.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people, color: Colors.blue, size: 20),
            const SizedBox(width: 8),
            Text(
              '$_userCount Enrolled ${_userCount == 1 ? 'User' : 'Users'}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.3), color.withOpacity(0.1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.5), width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 20),
          ],
        ),
      ),
    );
  }
}
