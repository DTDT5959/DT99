import '../../core/constants/app_constants.dart';

class Post {
  final String id;
  final String farmId;
  final String postCode; // e.g. "A-01"
  final PostColor color;
  final double positionX;
  final double positionY;
  final String? notes;
  final double? latitude; // future: GPS per post
  final double? longitude;
  final String? qrCode; // future: QR code attachment
  final DateTime createdAt;
  final DateTime updatedAt;

  const Post({
    required this.id,
    required this.farmId,
    required this.postCode,
    required this.color,
    required this.positionX,
    required this.positionY,
    this.notes,
    this.latitude,
    this.longitude,
    this.qrCode,
    required this.createdAt,
    required this.updatedAt,
  });

  Post copyWith({
    String? postCode,
    PostColor? color,
    double? positionX,
    double? positionY,
    String? notes,
    DateTime? updatedAt,
  }) {
    return Post(
      id: id,
      farmId: farmId,
      postCode: postCode ?? this.postCode,
      color: color ?? this.color,
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
      notes: notes ?? this.notes,
      latitude: latitude,
      longitude: longitude,
      qrCode: qrCode,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'farm_id': farmId,
        'post_code': postCode,
        'color': color.dbValue,
        'position_x': positionX,
        'position_y': positionY,
        'notes': notes,
        'latitude': latitude,
        'longitude': longitude,
        'qr_code': qrCode,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Post.fromMap(Map<String, dynamic> map) => Post(
        id: map['id'] as String,
        farmId: map['farm_id'] as String,
        postCode: map['post_code'] as String,
        color: PostColorX.fromDb(map['color'] as String),
        positionX: (map['position_x'] as num).toDouble(),
        positionY: (map['position_y'] as num).toDouble(),
        notes: map['notes'] as String?,
        latitude: (map['latitude'] as num?)?.toDouble(),
        longitude: (map['longitude'] as num?)?.toDouble(),
        qrCode: map['qr_code'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
}
