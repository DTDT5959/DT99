import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/analytics_service.dart';
import '../../data/models/photo.dart';
import '../../data/repositories/photo_repository.dart';

/// Read-only detail sheet for a single tree on the Analytics Map. Shows
/// the currently-filtered total plus lifetime stats (average/max/min),
/// and photos/notes if present. No editing controls — the Analytics Map
/// is a reporting surface, not the counting or layout screens.
class AnalyticsTreeDetailSheet extends StatelessWidget {
  final TreeAnalytics analytics;
  final String? notes;
  final SeasonView seasonView;
  final int? estimatedFruits;

  const AnalyticsTreeDetailSheet({
    super.key,
    required this.analytics,
    required this.seasonView,
    this.notes,
    this.estimatedFruits,
  });

  static Future<void> show(
    BuildContext context, {
    required TreeAnalytics analytics,
    required SeasonView seasonView,
    String? notes,
    int? estimatedFruits,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => AnalyticsTreeDetailSheet(
        analytics: analytics,
        seasonView: seasonView,
        notes: notes,
        estimatedFruits: estimatedFruits,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            Row(
              children: [
                Icon(Icons.circle, size: 14, color: analytics.color.swatch),
                const SizedBox(width: 8),
                Text('Post ${analytics.postCode}', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            Text(analytics.color.label, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: _Stat(
                        label: seasonView == SeasonView.fruit ? 'Est. Fruits (filter)' : 'Flowers (filter)',
                        value: seasonView == SeasonView.fruit
                            ? '${estimatedFruits ?? 0}'
                            : '${analytics.filteredTotal}',
                      ),
                    ),
                    Expanded(child: _Stat(label: 'Sessions', value: '${analytics.sessionCount}')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(child: _Stat(label: 'Average', value: analytics.averageFlowers.toStringAsFixed(1))),
                    Expanded(child: _Stat(label: 'Maximum', value: '${analytics.maxFlowers}')),
                    Expanded(child: _Stat(label: 'Minimum', value: '${analytics.minFlowers}')),
                  ],
                ),
              ),
            ),
            if ((notes ?? '').isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Notes', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(notes!, style: const TextStyle(fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 16),
            Text('Pictures', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _PostPhotos(postId: analytics.postId),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }
}

class _PostPhotos extends StatelessWidget {
  final String postId;
  const _PostPhotos({required this.postId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Photo>>(
      future: PhotoRepository().getPhotosForPost(postId),
      builder: (context, snapshot) {
        final photos = snapshot.data ?? const [];
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          );
        }
        if (photos.isEmpty) {
          return Text('No photos yet.', style: TextStyle(color: Colors.grey.shade600));
        }
        return SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) => ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(File(photos[i].imagePath), width: 80, height: 80, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(width: 80, height: 80, color: Colors.grey.shade200)),
            ),
          ),
        );
      },
    );
  }
}
