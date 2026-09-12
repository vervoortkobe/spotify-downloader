import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/screens/profile_screen.dart';

class TopBar extends StatelessWidget implements PreferredSizeWidget {
  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? action;
  final VoidCallback? onActionPressed;

  const TopBar({
    super.key,
    this.controller,
    this.hint = 'Search',
    this.onChanged,
    this.onSubmitted,
    this.action,
    this.onActionPressed,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 8,
      leadingWidth: 48,
      leading: Consumer<AuthProvider>(builder: (_, auth, _) => GestureDetector(
        onTap: () => Navigator.push(context, swipeRoute(const ProfileScreen())),
        child: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Center(
            child: Container(
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: SpotterfyTheme.card, width: 1.4), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 5)]),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: SpotterfyTheme.surface,
                backgroundImage: (auth.user?.photoUrl.isNotEmpty ?? false) ? NetworkImage(auth.user!.photoUrl) : null,
                child: (auth.user?.photoUrl.isEmpty ?? true) ? Icon(Icons.person, color: SpotterfyTheme.muted, size: 16) : null,
              ),
            ),
          ),
        ),
      )),
      title: Container(
        height: 36,
        decoration: BoxDecoration(color: SpotterfyTheme.card, borderRadius: BorderRadius.circular(18)),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: TextStyle(color: SpotterfyTheme.text, fontSize: 14),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search, color: SpotterfyTheme.muted, size: 18),
            prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 36),
            hintText: hint,
            hintStyle: TextStyle(color: SpotterfyTheme.muted, fontSize: 13),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            isDense: true,
            suffixIcon: (controller != null && controller!.text.isNotEmpty)
                ? IconButton(icon: Icon(Icons.clear, color: SpotterfyTheme.muted, size: 16), onPressed: () { controller!.clear(); onChanged?.call(''); }, padding: EdgeInsets.zero, constraints: const BoxConstraints())
                : null,
          ),
        ),
      ),
      actions: [
        if (action != null) Padding(padding: const EdgeInsets.only(right: 8), child: action!),
        const SizedBox(width: 4),
      ],
    );
  }
}
