import 'package:flutter/material.dart';
enum Severity { low, medium, high, emergency }

extension SeverityX on Severity {
  String get label {
    switch (this) {
      case Severity.low:
        return 'Low';
      case Severity.medium:
        return 'Medium';
      case Severity.high:
        return 'High';
      case Severity.emergency:
        return 'Emergency';
    }
  }
  Color get color {
    switch (this) {
      case Severity.low:
        return const Color(0xFF4CAF7D); 
      case Severity.medium:
        return const Color(0xFFE0B84C);
      case Severity.high:
        return const Color(0xFFE0813F); 
      case Severity.emergency:
        return const Color(0xFFE0524C); 
    }
  }

  IconData get icon {
    switch (this) {
      case Severity.low:
        return Icons.info_outline;
      case Severity.medium:
        return Icons.warning_amber_rounded;
      case Severity.high:
        return Icons.report_problem_rounded;
      case Severity.emergency:
        return Icons.emergency_rounded;
    }
  }
}
enum PinCategory { medical, hazard, obstacle, resource }

extension PinCategoryX on PinCategory {
  String get label {
    switch (this) {
      case PinCategory.medical:
        return 'Medical';
      case PinCategory.hazard:
        return 'Hazard';
      case PinCategory.obstacle:
        return 'Obstacle';
      case PinCategory.resource:
        return 'Resource';
    }
  }

  IconData get icon {
    switch (this) {
      case PinCategory.medical:
        return Icons.medical_services_rounded;
      case PinCategory.hazard:
        return Icons.dangerous_rounded;
      case PinCategory.obstacle:
        return Icons.block_rounded;
      case PinCategory.resource:
        return Icons.inventory_2_rounded;
    }
  }
}
@immutable
class Pin {
  final String id;
  final double lat;
  final double lng;
  final Severity severity;
  final PinCategory category;
  final String title;
  final String description;
  final String authorName;
  final DateTime createdAt;

  const Pin({
    required this.id,
    required this.lat,
    required this.lng,
    required this.severity,
    required this.category,
    required this.title,
    required this.description,
    required this.authorName,
    required this.createdAt,
  });
}
@immutable
class ThreadMessage {
  final String id;
  final String pinId;
  final String authorName;
  final String text;
  final DateTime timestamp;
  final bool isOwnDevice;
  final bool synced; 

  const ThreadMessage({
    required this.id,
    required this.pinId,
    required this.authorName,
    required this.text,
    required this.timestamp,
    required this.isOwnDevice,
    required this.synced,
  });
}
class MockData {
  static Pin samplePin() => Pin(
        id: 'pin_001',
        lat: 46.8523,
        lng: -121.7603,
        severity: Severity.high,
        category: PinCategory.medical,
        title: 'Twisted ankle, needs assistance',
        description:
            'Hiker fell near the switchback below Panorama Point. '
            'Conscious and stable, cannot bear weight on right ankle. '
            'Has water and shelter but requesting evac assistance.',
        authorName: 'J. Alvarez',
        createdAt: DateTime.now().subtract(const Duration(minutes: 47)),
      );

  static List<ThreadMessage> sampleThread(String pinId) => [
        ThreadMessage(
          id: 'msg_001',
          pinId: pinId,
          authorName: 'J. Alvarez',
          text: 'Posted the pin — we are about 200m below the marked '
              'trailhead junction, east side of the ridge.',
          timestamp: DateTime.now().subtract(const Duration(minutes: 47)),
          isOwnDevice: false,
          synced: true,
        ),
        ThreadMessage(
          id: 'msg_002',
          pinId: pinId,
          authorName: 'Ranger Kim',
          text: 'Copy that. Dispatching a two-person team from the '
              'south trailhead, ETA ~35 min.',
          timestamp: DateTime.now().subtract(const Duration(minutes: 41)),
          isOwnDevice: false,
          synced: true,
        ),
        ThreadMessage(
          id: 'msg_003',
          pinId: pinId,
          authorName: 'You',
          text: 'We can splint and keep her warm until they arrive.',
          timestamp: DateTime.now().subtract(const Duration(minutes: 38)),
          isOwnDevice: true,
          synced: true,
        ),
        ThreadMessage(
          id: 'msg_004',
          pinId: pinId,
          authorName: 'You',
          text: 'Splint is on, she is stable. Still no cell signal here.',
          timestamp: DateTime.now().subtract(const Duration(minutes: 4)),
          isOwnDevice: true,
          synced: false,
        ),
      ];
}
