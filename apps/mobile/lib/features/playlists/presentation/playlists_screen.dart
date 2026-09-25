import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/repositories/fadhkur_repository.dart';
import '../../../core/services/audio_playback_service.dart';

class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    final plNotifier = ref.read(playlistsProvider.notifier);
    final audioNotifier = ref.read(audioPlaybackProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('قوائم التشغيل القرآنية'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF2E9E9E),
        foregroundColor: Colors.white,
        onPressed: () {
          _showCreatePlaylistDialog(context, plNotifier);
        },
        icon: const Icon(Icons.add),
        label: const Text('قائمة جديدة'),
      ),
      body: playlists.isEmpty
          ? const Center(child: Text('لم تقم بإنشاء قوائم تشغيل بعد'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: playlists.length,
              itemBuilder: (ctx, i) {
                final pl = playlists[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ExpansionTile(
                    leading: const Icon(Icons.playlist_play, color: Color(0xFF2E9E9E), size: 32),
                    title: Text(pl.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${pl.items.length} تلاوات'),
                    trailing: PopupMenuButton(
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'rename', child: Text('إعادة تسمية')),
                        const PopupMenuItem(value: 'delete', child: Text('حذف القائمة')),
                      ],
                      onSelected: (val) {
                        if (val == 'delete') {
                          plNotifier.deletePlaylist(pl.id);
                        } else if (val == 'rename') {
                          _showRenameDialog(context, plNotifier, pl.id, pl.name);
                        }
                      },
                    ),
                    children: pl.items.isEmpty
                        ? [
                            const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text('القائمة فارغة، أضف تلاوات من شاشة القراء أو السور', style: TextStyle(color: Color(0xFF5B677A))),
                            )
                          ]
                        : pl.items.map((item) {
                            return ListTile(
                              leading: const Icon(Icons.music_note, color: Color(0xFFC77955)),
                              title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(item.subtitle),
                              trailing: IconButton(
                                icon: const Icon(Icons.play_arrow, color: Color(0xFF243B6B)),
                                onPressed: item.audioUrl.isEmpty
                                    ? null
                                    : () => audioNotifier.playQuranTrack(
                                          item.title,
                                          item.subtitle,
                                          item.audioUrl,
                                        ),
                              ),
                            );
                          }).toList(),
                  ),
                );
              },
            ),
    );
  }

  static void _showCreatePlaylistDialog(BuildContext context, PlaylistsNotifier notifier) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إنشاء قائمة تشغيل جديدة'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'مثال: ورد قيام الليل'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                notifier.createPlaylist(controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('إنشاء'),
          ),
        ],
      ),
    );
  }

  static void _showRenameDialog(BuildContext context, PlaylistsNotifier notifier, String id, String current) {
    final controller = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إعادة تسمية القائمة'),
        content: TextField(controller: controller),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                notifier.renamePlaylist(id, controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}
