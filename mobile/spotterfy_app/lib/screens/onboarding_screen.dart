import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/screens/main_screen.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late TextEditingController _nameController;
  late TextEditingController _urlController;
  bool _loading = false;
  String? _nameError;
  String? _urlError;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    final initialName = (user?.displayName ?? '').trim();
    _nameController = TextEditingController(text: initialName);
    _urlController = TextEditingController(text: user?.spotifyProfileUrl ?? '');
    _nameController.addListener(_validateName);
  }

  void _validateName() {
    final t = _nameController.text.trim();
    setState(() {
      if (t.isEmpty || t.length < 3) {
        _nameError = t.isEmpty ? 'Name is required' : 'At least 3 characters';
      } else {
        _nameError = null;
      }
    });
  }

  bool _validate() {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    bool ok = true;
    if (name.isEmpty || name.length < 3) {
      setState(() => _nameError = name.isEmpty ? 'Name is required' : 'At least 3 characters');
      ok = false;
    }
    if (url.isNotEmpty && !url.contains('open.spotify.com')) {
      setState(() => _urlError = 'Must be a Spotify profile URL');
      ok = false;
    } else {
      setState(() => _urlError = null);
    }
    return ok;
  }

  Future<void> _complete() async {
    if (!_validate()) return;
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    try {
      await auth.completeOnboarding(
        displayName: _nameController.text,
        spotifyUrl: _urlController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _skip() async {
    final auth = context.read<AuthProvider>();
    await auth.skipOnboarding();
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final photo = user?.photoUrl ?? '';
    final firstName = (user?.displayName ?? '').split(' ').firstWhere((e) => e.isNotEmpty, orElse: () => 'there');
    return Scaffold(
      backgroundColor: const Color(0xFF07110b),
      body: Stack(
        children: [
          CustomPaint(size: Size.infinite, painter: _OnboardingWavesPainter()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Google avatar and name
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF10b981), width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF10b981).withValues(alpha: 0.3),
                                blurRadius: 16,
                              )
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 48,
                            backgroundColor: const Color(0xFF0f1d17),
                            backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                            child: photo.isEmpty ? const Icon(Icons.person, size: 48, color: Color(0xFFa1a1aa)) : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          user?.displayName ?? 'User',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Hi, $firstName',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Welcome to Spotterfy',
                      style: TextStyle(
                        color: Color(0xFF10b981),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Set up your profile to continue.\nYour display name will be visible to others.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFa1a1aa),
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),
                    // Name field
                    Align(alignment: Alignment.centerLeft, child: Text('Display name', style: TextStyle(color: const Color(0xFFa1a1aa), fontSize: 12, fontWeight: FontWeight.w600))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nameController,
                      style: const TextStyle(color: Colors.white),
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: 'Your name',
                        errorText: _nameError,
                        hintStyle: const TextStyle(color: Color(0xFF6A6A6A)),
                        filled: true,
                        fillColor: const Color(0xFF0a1410),
                        prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF10b981), size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1a3a2a))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _nameError != null ? const Color(0xFFef4444) : const Color(0xFF1a3a2a))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF10b981), width: 1.5)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(alignment: Alignment.centerLeft, child: Text('Spotify profile URL (optional)', style: TextStyle(color: const Color(0xFFa1a1aa), fontSize: 12, fontWeight: FontWeight.w600))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _urlController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'https://open.spotify.com/user/...',
                        errorText: _urlError,
                        hintStyle: const TextStyle(color: Color(0xFF6A6A6A), fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFF0a1410),
                        prefixIcon: const Icon(Icons.link, color: Color(0xFF10b981), size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1a3a2a))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _urlError != null ? const Color(0xFFef4444) : const Color(0xFF1a3a2a))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF10b981), width: 1.5)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      ),
                      onChanged: (_) => setState(() => _urlError = null),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _complete,
                        style: ElevatedButton.styleFrom(backgroundColor: SpotterfyTheme.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        child: _loading
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Complete profile', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton(
                        onPressed: _loading ? null : _skip,
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF1a3a2a)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        child: const Text('Skip for now', style: TextStyle(color: Color(0xFFa1a1aa), fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('You can complete your profile later in settings.\nUntil then, onboarding will show on each launch.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF6A6A6A), fontSize: 11)),
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

class _OnboardingWavesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p1 = Paint()
      ..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [const Color(0xFF10b981).withValues(alpha: 0.12), const Color(0xFF10b981).withValues(alpha: 0.0)]).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;
    final path1 = Path()
      ..moveTo(0, size.height * 0.65)
      ..quadraticBezierTo(size.width * 0.3, size.height * 0.55, size.width * 0.6, size.height * 0.6)
      ..quadraticBezierTo(size.width * 0.8, size.height * 0.65, size.width, size.height * 0.55)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path1, p1);
    final p2 = Paint()
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [const Color(0xFF065f46).withValues(alpha: 0.08), const Color(0xFF065f46).withValues(alpha: 0.0)]).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;
    final path2 = Path()
      ..moveTo(0, size.height * 0.75)
      ..quadraticBezierTo(size.width * 0.25, size.height * 0.7, size.width * 0.5, size.height * 0.75)
      ..quadraticBezierTo(size.width * 0.75, size.height * 0.8, size.width, size.height * 0.72)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path2, p2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
