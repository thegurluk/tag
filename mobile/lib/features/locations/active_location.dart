import 'package:flutter/material.dart';

enum AlertColor {
  red,
  yellow,
  blue,
  expired;

  static AlertColor fromApi(String value) {
    return AlertColor.values.firstWhere(
      (color) => color.name == value,
      orElse: () => AlertColor.red,
    );
  }
}

class ActiveLocation {
  const ActiveLocation({
    required this.id,
    required this.title,
    required this.latitude,
    required this.longitude,
    required this.formattedAddress,
    required this.createdAt,
    required this.expiresAt,
    required this.color,
    required this.ageMinutes,
  });

  final String id;
  final String title;
  final double latitude;
  final double longitude;
  final String formattedAddress;
  final DateTime createdAt;
  final DateTime expiresAt;
  final AlertColor color;
  final int ageMinutes;

  factory ActiveLocation.fromJson(Map<String, dynamic> json) {
    return ActiveLocation(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Konum bildirimi',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      formattedAddress: json['formatted_address'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
      color: AlertColor.fromApi(json['color'] as String? ?? 'red'),
      ageMinutes: (json['age_minutes'] as num?)?.toInt() ?? 0,
    );
  }

  Color get accentColor {
    return switch (color) {
      AlertColor.red => const Color(0xFFD7352A),
      AlertColor.yellow => const Color(0xFFE0A820),
      AlertColor.blue => const Color(0xFF2F6FDB),
      AlertColor.expired => const Color(0xFF77808A),
    };
  }

  String get statusLabel {
    return switch (color) {
      AlertColor.red => 'Yeni',
      AlertColor.yellow => 'Takipte',
      AlertColor.blue => 'Eskiyor',
      AlertColor.expired => 'Suresi doldu',
    };
  }
}
