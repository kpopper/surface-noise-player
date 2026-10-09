import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/release.dart';
import '../services/library_provider.dart';
import '../utils/tag_colors.dart';
import 'add_tag_prompt.dart';
import 'art_thumbnail.dart';

const double kReleaseGridTilePadding = 8;

const double _textGap = 8;
const double _nameFontSize = 14;
const double _subtitleFontSize = 12;
// An explicit line height makes each line exactly fontSize × this tall,
// whatever the platform font's own metrics, so the text area's height can
// be computed up front.
const double _lineHeight = 1.3;

// Height of the text area beneath the cover — up to two lines of name plus
// one of tags or track count — at the user's text size, so the grid can size
// rows without measuring tiles (see LibraryScreen).
double releaseGridTileTextHeight(TextScaler scaler) =>
    (_textGap +
            scaler.scale(_nameFontSize) * _lineHeight * 2 +
            scaler.scale(_subtitleFontSize) * _lineHeight)
        .ceilToDouble() +
    1;

// A release in the wide layout's cover grid. Right-click (secondary tap)
// opens a context menu with the release screen's tag and rescan actions.
class ReleaseGridTile extends StatelessWidget {
  final Release release;
  final VoidCallback onTap;

  const ReleaseGridTile(
      {super.key, required this.release, required this.onTap});

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(value: 'tag', child: Text('Add tag…')),
        PopupMenuItem(value: 'rescan', child: Text('Rescan metadata')),
      ],
    );
    if (!context.mounted) return;
    switch (action) {
      case 'tag':
        await showAddTagPrompt(context, release);
      case 'rescan':
        await context.read<LibraryProvider>().rescanRelease(release);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        onSecondaryTapUp: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: Padding(
          padding: const EdgeInsets.all(kReleaseGridTilePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) => ArtThumbnail(
                    artPath: release.artPath, size: constraints.maxWidth),
              ),
              SizedBox(
                height:
                    releaseGridTileTextHeight(MediaQuery.textScalerOf(context)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: _textGap),
                    Text(
                      release.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: _nameFontSize,
                          height: _lineHeight,
                          fontWeight: FontWeight.w600),
                    ),
                    _subtitle(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _subtitle() {
    if (release.tags.isEmpty) {
      return Text('${release.tracks.length} tracks',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: _subtitleFontSize,
              height: _lineHeight,
              color: Colors.grey));
    }
    return Text.rich(
      TextSpan(
        children: [
          for (int i = 0; i < release.tags.length; i++) ...[
            if (i > 0)
              const TextSpan(text: ' · ', style: TextStyle(color: Colors.grey)),
            TextSpan(
              text: release.tags[i],
              style: TextStyle(color: tagColor(release.tags[i])),
            ),
          ],
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: _subtitleFontSize, height: _lineHeight),
    );
  }
}
