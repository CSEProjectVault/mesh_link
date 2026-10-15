import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/pin_models.dart';
import '../services/location_service.dart';
import '../widgets/pin_map.dart';

/// Full-screen map for a single report: its pin, your position, the distance
/// between the two, and the report's coordinates ready to copy and read out
/// to a rescue team over radio or phone.
class ReportMapScreen extends StatelessWidget {
  final Pin pin;

  const ReportMapScreen({super.key, required this.pin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coords = formatLatLng(pin.lat, pin.lng);

    return Scaffold(
      appBar: AppBar(
        title: Text(pin.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          Expanded(child: PinMap(pins: [pin], focusPin: pin)),
          Material(
            color: theme.colorScheme.surfaceContainerLow,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
                child: Row(
                  children: [
                    Icon(pin.severity.icon, color: pin.severity.color),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Report location',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          SelectableText(
                            coords,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy coordinates',
                      icon: const Icon(Icons.copy),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: coords));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Coordinates copied')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
