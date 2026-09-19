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
  late PageController _pageController;
  int _page = 0;
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
    _pageController = PageController();
    _nameController.addListener(_validateNameLive);
    // initial validation
    _validateNameLive();
  }

  void _validateNameLive() {
    final t = _nameController.text.trim();
    final err = t.isEmpty ? 'Name is required' : (t.length < 3 ? 'At least 3 characters' : null);
    if (err != _nameError) setState(() => _nameError = err);
  }

  bool get _nameValid => _nameError == null && _nameController.text.trim().isNotEmpty;

  bool _isUrlValid(String v) => v.isEmpty || v.contains('open.spotify.com');

  void _next() {
    if (_page == 0) {
      if (!_nameValid) {
        setState(() => _nameError = _nameController.text.trim().isEmpty ? 'Name is required' : 'At least 3 characters');
        return;
      }
      _pageController.animateToPage(1, duration: const Duration(milliseconds: 280), curve: Curves.easeInOut);
    } else {
      _complete();
    }
  }

  void _prev() {
    if (_page == 1) {
      _pageController.animateToPage(0, duration: const Duration(milliseconds: 280), curve: Curves.easeInOut);
    }
  }

  Future<void> _complete() async {
    if (!_nameValid) {
      _pageController.animateToPage(0, duration: const Duration(milliseconds: 280), curve: Curves.easeInOut);
      return;
    }
    final url = _urlController.text.trim();
    if (!_isUrlValid(url)) {
      setState(() => _urlError = 'Must be a Spotify profile URL');
      return;
    }
    setState(() {
      _loading = true;
      _urlError = null;
    });
    final auth = context.read<AuthProvider>();
    try {
      await auth.completeOnboarding(displayName: _nameController.text.trim(), spotifyUrl: url);
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
    _pageController.dispose();
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
            child: Column(
              children: [
                const SizedBox(height: 16),
                // avatar + greeting fixed header
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF10b981), width: 3),
                        boxShadow: [BoxShadow(color: const Color(0xFF10b981).withValues(alpha: 0.3), blurRadius: 16)],
                      ),
                      child: CircleAvatar(
                        radius: 36,
                        backgroundColor: const Color(0xFF0f1d17),
                        backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                        child: photo.isEmpty ? const Icon(Icons.person, size: 36, color: Color(0xFFa1a1aa)) : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(user?.displayName ?? 'User', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text('Hi, $firstName', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    const Text('Welcome to Spotterfy', style: TextStyle(color: Color(0xFF10b981), fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (i) => setState(() => _page = i),
                    children: [
                      _buildNamePage(),
                      _buildSpotifyPage(),
                    ],
                  ),
                ),
                // dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(2, (i) {
                    final active = i == _page;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: active ? const Color(0xFF10b981) : const Color(0xFF1a3a2a),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                // bottom nav
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Row(
                    children: [
                      if (_page == 1)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _loading ? null : _prev,
                            style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF1a3a2a)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 14)),
                            child: const Text('Previous', style: TextStyle(color: Color(0xFFa1a1aa), fontWeight: FontWeight.w600)),
                          ),
                        )
                      else
                        TextButton(
                          onPressed: _loading ? null : _skip,
                          child: const Text('Skip', style: TextStyle(color: Color(0xFF6A6A6A), fontWeight: FontWeight.w600)),
                        ),
                      if (_page == 1) const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _loading ? null : _next,
                          style: ElevatedButton.styleFrom(backgroundColor: SpotterfyTheme.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 14)),
                          child: _loading
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text(_page == 0 ? 'Next' : 'Complete', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_page == 0 ? 'Step 1 of 2 — Display name' : 'Step 2 of 2 — Spotify profile (optional)', style: const TextStyle(color: Color(0xFF6A6A6A), fontSize: 11)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNamePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Choose a display name', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('This will be visible to others. You can change it later in settings.', style: TextStyle(color: Color(0xFFa1a1aa), fontSize: 13, height: 1.4)),
          const SizedBox(height: 20),
          Text('Display name', style: TextStyle(color: const Color(0xFFa1a1aa), fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.words,
            autofocus: true,
            onSubmitted: (_) => _next(),
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF0a1410), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF1a3a2a))),
            child: Row(children: const [Icon(Icons.info_outline, color: Color(0xFF10b981), size: 18), SizedBox(width: 8), Expanded(child: Text('At least 3 characters. Swipe or tap Next to continue.', style: TextStyle(color: Color(0xFF6A6A6A), fontSize: 12)))]),
          ),
        ],
      ),
    );
  }

  Widget _buildSpotifyPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Connect Spotify (optional)', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Paste your Spotify profile URL to let friends find your playlists faster. You can skip this.', style: TextStyle(color: Color(0xFFa1a1aa), fontSize: 13, height: 1.4)),
          const SizedBox(height: 20),
          Text('Spotify profile URL', style: TextStyle(color: const Color(0xFFa1a1aa), fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _urlController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            keyboardType: TextInputType.url,
            onSubmitted: (_) => _complete(),
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
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF0a1410), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF1a3a2a))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Row(children: [Icon(Icons.lightbulb_outline, color: Color(0xFF10b981), size: 18), SizedBox(width: 8), Text('How to find it', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))]),
              SizedBox(height: 6),
              Text('Open Spotify → Your Profile → Share → Copy link', style: TextStyle(color: Color(0xFF6A6A6A), fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 20),
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
          const Center(child: Text('You can complete this later in settings.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF6A6A6A), fontSize: 11))),
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
