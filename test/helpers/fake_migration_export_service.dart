import 'package:surface_noise_player/models/release.dart';
import 'package:surface_noise_player/services/migration_export_service.dart';

class FakeMigrationExportService implements MigrationExportService {
  String? exportedRootPath;
  List<Release>? exportedReleases;
  int exportCallCount = 0;

  String? importCalledWithRootPath;
  int importCallCount = 0;
  bool importResult = false;

  @override
  Future<void> exportTo(String rootPath, List<Release> releases) async {
    exportCallCount++;
    exportedRootPath = rootPath;
    exportedReleases = releases;
  }

  @override
  Future<bool> importIfPresent(String rootPath) async {
    importCallCount++;
    importCalledWithRootPath = rootPath;
    return importResult;
  }
}
