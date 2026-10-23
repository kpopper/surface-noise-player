import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/release.dart';
import '../services/library_provider.dart';
import '../widgets/floating_player.dart';
import '../widgets/library_search_field.dart';
import '../widgets/release_card.dart';
import '../widgets/release_grid_tile.dart';
import '../widgets/tag_filter_bar.dart';
import '../widgets/tag_sidebar_list.dart';
import 'release_screen.dart';

class LibraryScreen extends StatefulWidget {
  // Wide layout (see AppShell): a sidebar with search, sort and tags beside
  // a cover grid, instead of the phone's list with filter chips above and
  // search below.
  final bool wide;
  // Called instead of pushing a ReleaseScreen when a release is opened.
  final ValueChanged<Release>? onReleaseSelected;
  // Wide layout only: shown in place of the grid (the open release), with
  // the sidebar still alongside it.
  final Widget? wideDetail;
  // Wide layout only: back to the grid — the sidebar's Home item, or a
  // filter changing while wideDetail is showing.
  final VoidCallback? onHome;
  final FocusNode? searchFocusNode;

  const LibraryScreen({
    super.key,
    this.wide = false,
    this.onReleaseSelected,
    this.wideDetail,
    this.onHome,
    this.searchFocusNode,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

const double kLibrarySidebarWidth = 260;

class _LibraryScreenState extends State<LibraryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LibraryProvider>().init();
    });
  }

  void _pickFolder() => context.read<LibraryProvider>().pickFolder();

  void _openRelease(Release release) {
    final onSelected = widget.onReleaseSelected;
    if (onSelected != null) {
      onSelected(release);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReleaseScreen(release: release)),
    );
  }

  Widget _sortToggle(LibraryProvider lib) => IconButton(
        icon: Icon(lib.sortMode == LibrarySortMode.recency
            ? Icons.unfold_more
            : Icons.sort_by_alpha),
        tooltip: lib.sortMode == LibrarySortMode.recency
            ? 'Sorted by recent activity — tap to sort alphabetically'
            : 'Sorted alphabetically — tap to sort by recent activity',
        onPressed: lib.toggleSortMode,
      );

  List<Widget> _libraryActions(LibraryProvider lib) => [
        IconButton(
          icon: const Icon(Icons.folder_open),
          tooltip: 'Choose library folder',
          onPressed: lib.loading ? null : _pickFolder,
        ),
        if (lib.loading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh library',
            onPressed: () => context.read<LibraryProvider>().refresh(),
          ),
      ];

  // Tapping anywhere outside an interactive control (release cards and the
  // search field itself both handle their own taps first, so this only
  // fires on genuinely "away" taps) dismisses the keyboard by moving focus
  // off the search field.
  Widget _dismissKeyboardOnTap(Widget child) => GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryProvider>(
      builder: (context, lib, _) {
        if (widget.wide) return _buildWide(lib);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Surface Noise'),
            actions: _libraryActions(lib),
          ),
          body: _dismissKeyboardOnTap(_buildBody(context, lib)),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, LibraryProvider lib) {
    // Blank until the initial database load resolves, rather than briefly
    // showing the no-root CTA while rootPath is still its unset default.
    if (!lib.initialized) {
      return const SizedBox.shrink();
    }

    if (lib.rootPath == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.library_music, size: 72, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No library set up',
                style: TextStyle(fontSize: 18, color: Colors.grey)),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose Library Folder'),
              onPressed: _pickFolder,
            ),
          ],
        ),
      );
    }

    final releases = lib.releases;

    // Already-known releases stay visible and interactive while a sync runs
    // in the background (the app bar spinner is the sync indicator) — only
    // fall back to a full-screen spinner when there's genuinely nothing to
    // show yet, e.g. the very first sync after picking a new folder.
    if (releases.isEmpty &&
        lib.activeTags.isEmpty &&
        !lib.untaggedActive &&
        lib.searchQuery.isEmpty) {
      if (lib.loading) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.album, size: 72, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No releases found',
                style: TextStyle(fontSize: 18, color: Colors.grey)),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose a Different Folder'),
              onPressed: _pickFolder,
            ),
          ],
        ),
      );
    }

    if (widget.wide) {
      return releases.isEmpty
          ? const Center(
              child: Text(
                'No releases match the current filters',
                style: TextStyle(color: Colors.grey),
              ),
            )
          : _buildGrid(releases);
    }

    return Column(
      children: [
        const TagFilterBar(),
        if (releases.isEmpty)
          const Expanded(
            child: Center(
              child: Text(
                'No releases match the current filters',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount: releases.length,
              itemBuilder: (context, i) {
                final release = releases[i];
                return ReleaseCard(
                  release: release,
                  onTap: () => _openRelease(release),
                );
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              Expanded(
                  child: LibrarySearchField(focusNode: widget.searchFocusNode)),
              const SizedBox(width: 8),
              _sortToggle(lib),
            ],
          ),
        ),
      ],
    );
  }

  // Filtering only makes sense against the grid, so a filter change while a
  // release is showing goes back to it.
  void _onFiltersChanged() {
    if (widget.wideDetail != null) widget.onHome?.call();
  }

  // Two panels, like Apple Music: the sidebar running the full height of
  // the window, and a main panel with its own navigation bar — the
  // Library one over the grid, or the open release's in its place.
  Widget _buildWide(LibraryProvider lib) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: kLibrarySidebarWidth, child: _buildSidebar()),
        const VerticalDivider(width: 1),
        Expanded(
          child: widget.wideDetail ??
              Scaffold(
                appBar: AppBar(
                  title: const Text('Library'),
                  actions: [
                    SizedBox(
                      width: 220,
                      child: LibrarySearchField(
                          focusNode: widget.searchFocusNode, compact: true),
                    ),
                    const SizedBox(width: 8),
                    _sortToggle(lib),
                    ..._libraryActions(lib),
                  ],
                ),
                body: _dismissKeyboardOnTap(_buildBody(context, lib)),
              ),
        ),
      ],
    );
  }

  Widget _buildSidebar() {
    final scheme = Theme.of(context).colorScheme;
    // A Material (not a ColoredBox) so the Home and tag rows' highlights and
    // ink splashes paint on it rather than being hidden underneath.
    return Material(
      color: scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: ListTile(
              dense: true,
              selected: widget.wideDetail == null,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              selectedTileColor: scheme.secondaryContainer,
              leading: const Icon(Icons.home_outlined, size: 20),
              minLeadingWidth: 20,
              title: const Text('Home'),
              onTap: widget.onHome,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Tags', style: Theme.of(context).textTheme.titleSmall),
          ),
          Expanded(
            child: TagSidebarList(onTagToggled: (_) => _onFiltersChanged()),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<Release> releases) {
    const outerPadding = 12.0;
    const spacing = 8.0;
    const maxTileWidth = 200.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fixed row height (square cover plus a fixed text area) computed
        // from the column width, so tiles never overflow or leave gaps.
        final available = constraints.maxWidth - outerPadding * 2;
        final columns = ((available + spacing) / (maxTileWidth + spacing))
            .ceil()
            .clamp(1, 1000);
        final tileWidth = (available - spacing * (columns - 1)) / columns;
        return GridView.builder(
          // Restores the scroll position on returning from a release.
          key: const PageStorageKey('release-grid'),
          padding: const EdgeInsets.fromLTRB(outerPadding, outerPadding,
              outerPadding, kFloatingPlayerClearance),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent: tileWidth +
                releaseGridTileTextHeight(MediaQuery.textScalerOf(context)),
          ),
          itemCount: releases.length,
          itemBuilder: (context, i) {
            final release = releases[i];
            return ReleaseGridTile(
              release: release,
              onTap: () => _openRelease(release),
            );
          },
        );
      },
    );
  }
}
