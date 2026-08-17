import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/models/photo.dart';
import '../../../data/models/post.dart';
import '../../../data/repositories/flower_count_repository.dart';
import '../../../data/repositories/photo_repository.dart';
import '../../../data/repositories/post_repository.dart';

/// Reached via a long-press on any post, on the layout editor or the
/// counting canvas — shows everything known about a single post over time.
class PostHistoryScreen extends StatefulWidget {
  final String postId;
  const PostHistoryScreen({super.key, required this.postId});

  @override
  State<PostHistoryScreen> createState() => _PostHistoryScreenState();
}

class _PostHistoryScreenState extends State<PostHistoryScreen> {
  final _postRepo = PostRepository();
  final _countRepo = FlowerCountRepository();
  final _photoRepo = PhotoRepository();
  final _picker = ImagePicker();

  Post? _post;
  List<Map<String, dynamic>> _history = [];
  List<Photo> _photos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final post = await _postRepo.getPost(widget.postId);
    final history = await _countRepo.getHistoryForPost(widget.postId);
    final photos = await _photoRepo.getPhotosForPost(widget.postId);
    if (!mounted) return;
    setState(() {
      _post = post;
      _history = history.map((h) => {'date': h.date, 'count': h.flowerCount}).toList();
      _photos = photos;
      _loading = false;
    });
  }

  Future<void> _addPhoto() async {
    final picked = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (picked == null) return;
    await _photoRepo.addPhoto(postId: widget.postId, imagePath: picked.path);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    return Scaffold(
      appBar: AppBar(title: Text(post == null ? 'Post' : 'Post ${post.postCode}')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addPhoto,
        child: const Icon(Icons.add_a_photo),
      ),
      body: _loading || post == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.circle, color: post.color.swatch, size: 14),
                            const SizedBox(width: 8),
                            Text('Variety: ${post.color.label}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('Created ${DateFormat.yMMMd().format(post.createdAt)}',
                            style: TextStyle(color: Colors.grey.shade600)),
                        if ((post.notes ?? '').isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(post.notes!, style: const TextStyle(fontStyle: FontStyle.italic)),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Flower History', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_history.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('No counts recorded yet.', style: TextStyle(color: Colors.grey.shade600)),
                  )
                else
                  Card(
                    child: Column(
                      children: _history
                          .map((h) => ListTile(
                                title: Text(DateFormat.yMMMd().format(h['date'] as DateTime)),
                                trailing: Text('${h['count']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                              ))
                          .toList(),
                    ),
                  ),
                const SizedBox(height: 20),
                Text('Photos', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_photos.isEmpty)
                  Text('No photos yet. Tap the camera button to add one.',
                      style: TextStyle(color: Colors.grey.shade600))
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: _photos.length,
                    itemBuilder: (context, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(File(_photos[i].imagePath), fit: BoxFit.cover),
                    ),
                  ),
              ],
            ),
    );
  }
}
