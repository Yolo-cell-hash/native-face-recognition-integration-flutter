import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Embedding storage service that handles face embeddings persistence.
/// Matches Python: save_embeddings, load_embeddings, delete_user_embeddings
class EmbeddingStorage {
  static const String _embeddingsFileName = 'face_embeddings.json';

  /// Get the embeddings file path
  static Future<File> _getEmbeddingsFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_embeddingsFileName');
  }

  /// Save user embedding to storage
  /// Matches Python: save_embeddings(embeddings, folder_name, embeddings_file)
  static Future<void> saveEmbedding(
    String userName,
    List<double> embedding,
  ) async {
    debugPrint('💾 EmbeddingStorage: Saving embedding for user: $userName');
    debugPrint('💾 EmbeddingStorage: Embedding dimension: ${embedding.length}');

    try {
      final embeddings = await loadAllEmbeddings();

      // Add or update user embeddings
      if (embeddings.containsKey(userName)) {
        embeddings[userName]!.add(embedding);
        debugPrint('💾 EmbeddingStorage: Added new embedding to existing user');
      } else {
        embeddings[userName] = [embedding];
        debugPrint('💾 EmbeddingStorage: Created new user entry');
      }

      await _saveToFile(embeddings);
      debugPrint('✅ EmbeddingStorage: Embedding saved successfully');
    } catch (e, stackTrace) {
      debugPrint('❌ EmbeddingStorage: Error saving embedding: $e');
      debugPrint('❌ EmbeddingStorage: Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Load all embeddings from storage
  /// Matches Python: load_embeddings(embeddings_file, device)
  static Future<Map<String, List<List<double>>>> loadAllEmbeddings() async {
    debugPrint('📂 EmbeddingStorage: Loading all embeddings...');

    try {
      final file = await _getEmbeddingsFile();

      if (!await file.exists()) {
        debugPrint(
          '📂 EmbeddingStorage: No embeddings file found, returning empty map',
        );
        return {};
      }

      final jsonString = await file.readAsString();
      if (jsonString.isEmpty) {
        debugPrint('📂 EmbeddingStorage: Empty embeddings file');
        return {};
      }

      final Map<String, dynamic> jsonData = jsonDecode(jsonString);
      final embeddings = <String, List<List<double>>>{};

      for (final entry in jsonData.entries) {
        final List<dynamic> userEmbeddings = entry.value;
        embeddings[entry.key] = userEmbeddings
            .map(
              (e) => (e as List<dynamic>)
                  .map((v) => (v as num).toDouble())
                  .toList(),
            )
            .toList();
      }

      debugPrint('✅ EmbeddingStorage: Loaded ${embeddings.length} users');
      for (final entry in embeddings.entries) {
        debugPrint(
          '📂 EmbeddingStorage: User ${entry.key} has ${entry.value.length} embeddings',
        );
      }

      return embeddings;
    } catch (e, stackTrace) {
      debugPrint('❌ EmbeddingStorage: Error loading embeddings: $e');
      debugPrint('❌ EmbeddingStorage: Stack trace: $stackTrace');
      return {};
    }
  }

  /// Delete user embeddings
  /// Matches Python: delete_user_embeddings(user_name, embeddings_file)
  static Future<bool> deleteUserEmbeddings(String userName) async {
    debugPrint('🗑️ EmbeddingStorage: Deleting embeddings for user: $userName');

    try {
      final embeddings = await loadAllEmbeddings();

      if (embeddings.containsKey(userName)) {
        embeddings.remove(userName);
        await _saveToFile(embeddings);
        debugPrint('✅ EmbeddingStorage: User $userName deleted successfully');
        return true;
      } else {
        debugPrint('⚠️ EmbeddingStorage: User $userName not found');
        return false;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ EmbeddingStorage: Error deleting user: $e');
      debugPrint('❌ EmbeddingStorage: Stack trace: $stackTrace');
      return false;
    }
  }

  /// Get list of enrolled user names
  static Future<List<String>> getEnrolledUsers() async {
    debugPrint('👥 EmbeddingStorage: Getting enrolled users...');
    final embeddings = await loadAllEmbeddings();
    final users = embeddings.keys.toList();
    debugPrint('👥 EmbeddingStorage: Found ${users.length} enrolled users');
    return users;
  }

  /// Get user count
  static Future<int> getUserCount() async {
    final embeddings = await loadAllEmbeddings();
    return embeddings.length;
  }

  /// Check if user exists
  static Future<bool> userExists(String userName) async {
    final embeddings = await loadAllEmbeddings();
    return embeddings.containsKey(userName);
  }

  /// Save embeddings to file
  static Future<void> _saveToFile(
    Map<String, List<List<double>>> embeddings,
  ) async {
    final file = await _getEmbeddingsFile();
    final jsonString = jsonEncode(embeddings);
    await file.writeAsString(jsonString);
    debugPrint('💾 EmbeddingStorage: Saved ${embeddings.length} users to file');
  }

  /// Clear all embeddings (for testing)
  static Future<void> clearAll() async {
    debugPrint('🗑️ EmbeddingStorage: Clearing all embeddings...');
    final file = await _getEmbeddingsFile();
    if (await file.exists()) {
      await file.delete();
      debugPrint('✅ EmbeddingStorage: All embeddings cleared');
    }
  }
}
