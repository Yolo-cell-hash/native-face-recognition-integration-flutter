class UserModel {
  final String id;
  final String name;
  final List<String> photoPaths;
  final DateTime enrolledAt;

  UserModel({
    required this.id,
    required this.name,
    required this.photoPaths,
    required this.enrolledAt,
  });

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'photoPaths': photoPaths,
      'enrolledAt': enrolledAt.toIso8601String(),
    };
  }

  // Create from JSON
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      name: json['name'] as String,
      photoPaths: List<String>.from(json['photoPaths'] as List),
      enrolledAt: DateTime.parse(json['enrolledAt'] as String),
    );
  }

  @override
  String toString() {
    return 'UserModel{id: $id, name: $name, photos: ${photoPaths.length}, enrolledAt: $enrolledAt}';
  }
}
