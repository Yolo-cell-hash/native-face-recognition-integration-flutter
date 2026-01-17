import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';

class UserStorageService {
  static const String _usersKey = 'enrolled_users';

  // Save all users to storage
  Future<void> saveUsers(List<UserModel> users) async {
    debugPrint('💾 UserStorage: Saving ${users.length} users...');
    try {
      final prefs = await SharedPreferences.getInstance();
      final usersJson = users.map((user) => user.toJson()).toList();
      final jsonString = jsonEncode(usersJson);

      await prefs.setString(_usersKey, jsonString);
      debugPrint('✅ UserStorage: Successfully saved ${users.length} users');

      for (var user in users) {
        debugPrint('💾 UserStorage: Saved user - $user');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ UserStorage: Error saving users: $e');
      debugPrint('❌ UserStorage: Stack trace: $stackTrace');
      rethrow;
    }
  }

  // Load all users from storage
  Future<List<UserModel>> loadUsers() async {
    debugPrint('📂 UserStorage: Loading users from storage...');
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_usersKey);

      if (jsonString == null || jsonString.isEmpty) {
        debugPrint('📂 UserStorage: No users found in storage');
        return [];
      }

      final List<dynamic> usersJson = jsonDecode(jsonString);
      final users = usersJson
          .map((json) => UserModel.fromJson(json as Map<String, dynamic>))
          .toList();

      debugPrint('✅ UserStorage: Loaded ${users.length} users from storage');
      for (var user in users) {
        debugPrint('📂 UserStorage: Loaded user - $user');
      }

      return users;
    } catch (e, stackTrace) {
      debugPrint('❌ UserStorage: Error loading users: $e');
      debugPrint('❌ UserStorage: Stack trace: $stackTrace');
      return [];
    }
  }

  // Add a new user
  Future<void> addUser(UserModel user) async {
    debugPrint('➕ UserStorage: Adding new user - ${user.name}');
    try {
      final users = await loadUsers();
      users.add(user);
      await saveUsers(users);
      debugPrint('✅ UserStorage: User ${user.name} added successfully');
    } catch (e, stackTrace) {
      debugPrint('❌ UserStorage: Error adding user: $e');
      debugPrint('❌ UserStorage: Stack trace: $stackTrace');
      rethrow;
    }
  }

  // Delete a user by ID
  Future<void> deleteUser(String userId) async {
    debugPrint('🗑️ UserStorage: Deleting user with ID: $userId');
    try {
      final users = await loadUsers();
      final initialCount = users.length;
      users.removeWhere((user) => user.id == userId);

      if (users.length < initialCount) {
        await saveUsers(users);
        debugPrint('✅ UserStorage: User deleted successfully');
      } else {
        debugPrint('⚠️ UserStorage: User with ID $userId not found');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ UserStorage: Error deleting user: $e');
      debugPrint('❌ UserStorage: Stack trace: $stackTrace');
      rethrow;
    }
  }

  // Get user count
  Future<int> getUserCount() async {
    debugPrint('🔢 UserStorage: Getting user count...');
    try {
      final users = await loadUsers();
      debugPrint('🔢 UserStorage: User count = ${users.length}');
      return users.length;
    } catch (e) {
      debugPrint('❌ UserStorage: Error getting user count: $e');
      return 0;
    }
  }

  // Find user by name (for verification)
  Future<UserModel?> findUserByName(String name) async {
    debugPrint('🔍 UserStorage: Searching for user by name: $name');
    try {
      final users = await loadUsers();
      final user = users
          .where((user) => user.name.toLowerCase() == name.toLowerCase())
          .firstOrNull;

      if (user != null) {
        debugPrint('✅ UserStorage: Found user - ${user.name}');
      } else {
        debugPrint('⚠️ UserStorage: User with name "$name" not found');
      }

      return user;
    } catch (e) {
      debugPrint('❌ UserStorage: Error finding user: $e');
      return null;
    }
  }

  // Clear all users (for testing)
  Future<void> clearAllUsers() async {
    debugPrint('🗑️ UserStorage: Clearing all users...');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_usersKey);
      debugPrint('✅ UserStorage: All users cleared');
    } catch (e, stackTrace) {
      debugPrint('❌ UserStorage: Error clearing users: $e');
      debugPrint('❌ UserStorage: Stack trace: $stackTrace');
    }
  }
}
