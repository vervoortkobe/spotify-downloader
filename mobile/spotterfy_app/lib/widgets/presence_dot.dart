import 'package:flutter/material.dart';

/// The shared online/offline marker used on friend avatars and in admin.
class PresenceDot extends StatelessWidget {
  final bool isOnline;
  final Color borderColor;

  const PresenceDot({
    super.key,
    required this.isOnline,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      color: isOnline ? const Color(0xFF22C55E) : const Color(0xFF71717A),
      shape: BoxShape.circle,
      border: Border.all(color: borderColor, width: 2),
    ),
  );
}
