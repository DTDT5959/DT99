class FlowerCount {
  final String id;
  final String postId;
  final DateTime date; // normalized to yyyy-MM-dd (session date)
  final int flowerCount;
  final String? countedBy; // future: multi-worker support
  final DateTime createdAt;
  final DateTime updatedAt;

  const FlowerCount({
    required this.id,
    required this.postId,
    required this.date,
    required this.flowerCount,
    this.countedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'post_id': postId,
        'date': _dateOnly(date),
        'flower_count': flowerCount,
        'counted_by': countedBy,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory FlowerCount.fromMap(Map<String, dynamic> map) => FlowerCount(
        id: map['id'] as String,
        postId: map['post_id'] as String,
        date: DateTime.parse(map['date'] as String),
        flowerCount: map['flower_count'] as int,
        countedBy: map['counted_by'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
