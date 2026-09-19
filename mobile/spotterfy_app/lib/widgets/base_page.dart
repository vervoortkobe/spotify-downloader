import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/screens/profile_screen.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';

/// Base scaffold for all main tab pages.
/// Provides a uniform AppBar with:
/// - leading account logo (top-left, navigates to Profile)
/// - centered search bar OR title
/// - optional trailing action (e.g. + on Library, group_add on Chat)
///
/// Pages can pass any [body] and keep their own logic
/// while sharing the same top bar look & feel.
class BasePageScaffold extends StatelessWidget {
  /// Search mode – pass a controller and hint to show the search bar.
  final TextEditingController? searchController;
  final String searchHint;
  final String query;
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<String>? onSearchSubmitted;

  /// Title mode – set [title] and leave [searchController] null to show a
  /// plain title instead of a search bar (e.g. Queue/Storage).
  final String? title;

  /// Optional trailing icon (e.g. IconButton). Rendered with uniform size/color.
  /// When null, 32px invisible padding is kept so the search bar width matches
  /// pages that DO have an action (Library/Chat).
  final Widget? action;

  final Widget body;
  final PreferredSizeWidget? bottom;
  final Widget? floatingActionButton;
  final Color? backgroundColor;

  const BasePageScaffold({
    super.key,
    this.searchController,
    this.searchHint = 'Search',
    this.query = '',
    this.onSearchChanged,
    this.onSearchSubmitted,
    this.title,
    this.action,
    required this.body,
    this.bottom,
    this.floatingActionButton,
    this.backgroundColor,
  }) : assert(
          searchController != null || title != null,
          'Either searchController or title must be provided',
        );

  @override
  Widget build(BuildContext context) {
    final bool isSearch = searchController != null;
    // Unified dark gradient like Jam/Chat page + Onboarding waves base
    const gradientBg = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF0d1f14), Color(0xFF07110b), Color(0xFF050a07)],
    );
    return Container(
      decoration: const BoxDecoration(gradient: gradientBg),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // keep pages visually identical; ignore per-page backgroundColor and use gradient
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          leadingWidth: 56,
          leading: Consumer<AuthProvider>(
            builder: (context, auth, child) => GestureDetector(
              onTap: () => Navigator.push(context, swipeRoute(const ProfileScreen())),
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Center(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: SpotterfyTheme.card, width: 1.6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 5,
                        )
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: SpotterfyTheme.surface,
                      backgroundImage: (auth.user?.photoUrl.isNotEmpty ?? false)
                          ? NetworkImage(auth.user!.photoUrl)
                          : null,
                      child: (auth.user?.photoUrl.isEmpty ?? true)
                          ? Icon(Icons.person, color: SpotterfyTheme.muted, size: 18)
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
          titleSpacing: 12,
          title: isSearch
              ? Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: SpotterfyTheme.card,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: TextField(
                    controller: searchController,
                    onChanged: onSearchChanged,
                    onSubmitted: onSearchSubmitted,
                    style: TextStyle(color: SpotterfyTheme.text, fontSize: 14),
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.search, color: SpotterfyTheme.muted, size: 18),
                      prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 36),
                      hintText: searchHint,
                      hintStyle: TextStyle(color: SpotterfyTheme.muted, fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      isDense: true,
                      suffixIcon: query.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, color: SpotterfyTheme.muted, size: 16),
                              onPressed: () {
                                searchController!.clear();
                                onSearchChanged?.call('');
                                onSearchSubmitted?.call('');
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            )
                          : null,
                    ),
                  ),
                )
              : Text(
                  title!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
          // Discover/Search have no trailing icon -> let search bar use full width (extra right padding only 12)
          // Library/Chat keep 48 for + / group_add so left edge stays same but right gives space
          actions: action != null
              ? [
                  SizedBox(
                    width: 48,
                    child: Center(child: Padding(padding: const EdgeInsets.only(right: 4), child: action)),
                  ),
                ]
              : const [
                  SizedBox(width: 12),
                ],
          bottom: bottom,
        ),
        body: body,
        floatingActionButton: floatingActionButton,
      ),
    );
  }
}
