import 'package:flutter/material.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

class ApprovalScreen extends StatelessWidget {
  const ApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotterfyTheme.pageBackground,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.hourglass_empty,
                color: SpotterfyTheme.primary,
                size: 72,
              ),
              const SizedBox(height: 24),
              Text(
                'Approval Pending',
                style: TextStyle(
                  color: SpotterfyTheme.text,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Your account is waiting for admin approval.\nYou\'ll be notified once approved.',
                style: TextStyle(color: SpotterfyTheme.mutedDark, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              CircularProgressIndicator(color: SpotterfyTheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
