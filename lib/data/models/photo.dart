class Photo {
  final String id;
  final String postId;
  final String imagePath;
  final DateTime createdAt;

  const Photo({
    required this.id,
    required this.postId,
    required this.imagePath,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'post_id': postId,
        'image_path': imagePath,
        'created_at': createdAt.toIso8601String(),
      };

  factory Photo.fromMap(Map<String, dynamic> map) => Photo(
        id: map['id'] as String,
        postId: map['post_id'] as String,
        imagePath: map['image_path'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}
