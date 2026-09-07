import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  bool _checking = true;
  bool _granted = false;
  List<FileSystemEntity> _files = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() { _checking = true; _error = null; });
    final status = await _requestPermission();
    if (!status) {
      setState(() { _granted = false; _checking = false; });
      return;
    }
    await _loadFiles();
    setState(() { _granted = true; _checking = false; });
  }

  Future<bool> _requestPermission() async {
    if (Platform.isAndroid) {
      // Android 13+ uses READ_MEDIA_AUDIO, older uses storage
      if (await Permission.audio.isGranted || await Permission.storage.isGranted) return true;
      var s = await Permission.audio.request();
      if (s.isGranted) return true;
      s = await Permission.storage.request();
      if (s.isGranted) return true;
      // Also try mediaLibrary for some OEMs
      s = await Permission.mediaLibrary.request();
      return s.isGranted;
    }
    return true;
  }

  Future<void> _loadFiles() async {
    try {
      final dirs = <Directory>[];
      // Common music dirs
      final ext = Directory('/storage/emulated/0/Music');
      if (await ext.exists()) dirs.add(ext);
      final dl = Directory('/storage/emulated/0/Download');
      if (await dl.exists()) dirs.add(dl);
      final all = <FileSystemEntity>[];
      for (final d in dirs) {
        try {
          final list = await d.list(recursive: false).toList();
          all.addAll(list.where((e) => e.path.toLowerCase().endsWith('.mp3') || e.path.toLowerCase().endsWith('.m4a') || e.path.toLowerCase().endsWith('.opus') || e.path.toLowerCase().endsWith('.flac') || e.path.toLowerCase().endsWith('.wav')));
        } catch (_) {}
      }
      // Also scan app's download dir via Spotterfy downloads if exists
      all.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      setState(() => _files = all);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotterfyTheme.background,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, title: Text('Storage', style: TextStyle(color: SpotterfyTheme.text, fontWeight: FontWeight.bold))),
      body: _checking
          ? Center(child: CircularProgressIndicator(color: SpotterfyTheme.primary))
          : !_granted
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.folder_off, size: 56, color: SpotterfyTheme.muted),
                      const SizedBox(height: 12),
                      Text('Permission needed', style: TextStyle(color: SpotterfyTheme.text, fontWeight: FontWeight.w600, fontSize: 16)),
                      const SizedBox(height: 6),
                      Text('Allow access to phone storage to display your downloaded music.', textAlign: TextAlign.center, style: TextStyle(color: SpotterfyTheme.muted, fontSize: 13)),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _check, child: const Text('Grant permission')),
                      TextButton(onPressed: () => openAppSettings(), child: Text('Open settings', style: TextStyle(color: SpotterfyTheme.primary))),
                    ]),
                  ),
                )
              : _error != null
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12), textAlign: TextAlign.center)))
                  : _files.isEmpty
                  ? Center(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.music_off, size: 56, color: SpotterfyTheme.muted),
                        const SizedBox(height: 12),
                        Text('No local music found', style: TextStyle(color: SpotterfyTheme.text, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text('Downloaded songs and phone music will appear here.', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12)),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(onPressed: _loadFiles, icon: const Icon(Icons.refresh, size: 18), label: const Text('Refresh')),
                      ]),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadFiles,
                      color: SpotterfyTheme.primary,
                      backgroundColor: SpotterfyTheme.surface,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 100, top: 8),
                        itemCount: _files.length,
                        itemBuilder: (_, i) {
                          final f = _files[i];
                          final name = f.path.split('/').last;
                          final stat = (() { try { return f.statSync(); } catch (_) { return null; } })();
                          final size = stat != null ? '${(stat.size / (1024 * 1024)).toStringAsFixed(1)} MB' : '';
                          return ListTile(
                            leading: Container(width: 48, height: 48, decoration: BoxDecoration(color: SpotterfyTheme.surface, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.audio_file, color: SpotterfyTheme.primary)),
                            title: Text(name, style: TextStyle(color: SpotterfyTheme.text, fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(size, style: TextStyle(color: SpotterfyTheme.muted, fontSize: 11)),
                            trailing: IconButton(icon: const Icon(Icons.play_circle_fill, color: SpotterfyTheme.primary), onPressed: () {
                              HapticFeedback.lightImpact();
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Playing local: $name')));
                            }),
                            onTap: () {},
                          );
                        },
                      ),
                    ),
    );
  }
}
