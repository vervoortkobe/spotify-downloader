import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/screens/login_screen.dart';

/// Shown instead of the app when the signed-in account has been suspended.
///
/// A blacklist that is only written and never read is not a blacklist, so this is
/// where a ban from the admin panel actually takes effect. Deliberately offers
/// only "sign out" - there is no in-app appeal, because routing that would mean
/// letting a banned client write to Firestore.
class SuspendedScreen extends StatelessWidget {
  const SuspendedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final reason = context.select<AuthProvider, String>((a) => a.bannedReason);

    return Scaffold(
      backgroundColor: const Color(0xFF07110b),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: const Color(0xFFef4444).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.gpp_maybe,
                    color: Color(0xFFef4444),
                    size: 44,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Account suspended',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  reason.isEmpty
                      ? 'This account has been suspended. Contact support if you think this is a mistake.'
                      : reason,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFa1a1aa),
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final auth = context.read<AuthProvider>();
                      await auth.signOut();
                      if (!context.mounted) return;
                      // Replace rather than push: there is nothing to go "back"
                      // to, and leaving this on the stack would let a swipe-back
                      // reveal the app again.
                      await Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => const LoginScreen(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0f1d17),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Sign out',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
