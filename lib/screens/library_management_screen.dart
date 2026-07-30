import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/folder_info.dart';
import '../services/library_provider.dart';

class LibraryManagementScreen extends StatefulWidget {
  const LibraryManagementScreen({super.key});

  @override
  State<LibraryManagementScreen> createState() => _LibraryManagementScreenState();
}

class _LibraryManagementScreenState extends State<LibraryManagementScreen> {
  List<FolderInfo>? _folders;
  final Set<String> _loadingPaths = {};
  final Set<String> _pendingDeselects = {};
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final lib = context.read<LibraryProvider>();
    if (lib.rootPath == null) return;
    final folders = await lib.listAllFolders();
    if (mounted) setState(() => _folders = folders);
  }

  Future<void> _toggle(FolderInfo folder) async {
    if (_loadingPaths.contains(folder.path) || _pendingDeselects.contains(folder.path)) return;
    final lib = context.read<LibraryProvider>();
    if (folder.isSelected) {
      setState(() => _pendingDeselects.add(folder.path));
      await lib.deselectRelease(folder.path);
      await _load();
      if (mounted) setState(() => _pendingDeselects.remove(folder.path));
    } else {
      setState(() => _loadingPaths.add(folder.path));
      await lib.selectRelease(folder.path);
      await _load();
      if (mounted) setState(() => _loadingPaths.remove(folder.path));
    }
  }

  Future<void> _changeFolder() async {
    final lib = context.read<LibraryProvider>();
    await lib.pickFolder();
    if (mounted) setState(() => _folders = null);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.folder_open),
          tooltip: 'Change folder',
          onPressed: _changeFolder,
        ),
        title: const Text('Manage Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Done',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Consumer<LibraryProvider>(
        builder: (context, lib, _) {
          if (lib.rootPath == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.library_music, size: 72, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No folder selected',
                      style: TextStyle(fontSize: 18, color: Colors.grey)),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Choose Library Folder'),
                    onPressed: _changeFolder,
                  ),
                ],
              ),
            );
          }

          if (_folders == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_folders!.isEmpty) {
            return const Center(
              child: Text(
                'No albums found in this folder',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          final query = _query.trim().toLowerCase();
          final visibleFolders = query.isEmpty
              ? _folders!
              : _folders!.where((f) => f.name.toLowerCase().contains(query)).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search albums',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: visibleFolders.isEmpty
                      ? const Center(
                          child: Text(
                            'No albums match your search',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          itemCount: visibleFolders.length,
                          itemBuilder: (context, i) {
                            final folder = visibleFolders[i];
                            final isLoading = _loadingPaths.contains(folder.path);
                            final isChecked =
                                folder.isSelected && !_pendingDeselects.contains(folder.path);
                            return ListTile(
                              title: Text(
                                folder.name,
                                style: TextStyle(
                                  fontWeight: isChecked ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              onTap: () => _toggle(folder),
                              trailing: isLoading
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Checkbox(
                                      value: isChecked,
                                      onChanged: (_) => _toggle(folder),
                                    ),
                            );
                          },
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
