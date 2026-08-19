import 'package:flutter/material.dart';

class ApprovalScreen extends StatelessWidget {
  const ApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07110b),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hourglass_empty, color: const Color(0xFF10b981), size: 72),
              const SizedBox(height: 24),
              Text('Approval Pending', style: TextStyle(
                color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold,
              )),
              const SizedBox(height: 12),
              Text(
                'Your account is waiting for admin approval.\nYou\'ll be notified once approved.',
                style: TextStyle(color: const Color(0xFFa1a1aa), fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              CircularProgressIndicator(color: const Color(0xFF10b981)),
            ],
          ),
        ),
      ),
    );
  }
}
