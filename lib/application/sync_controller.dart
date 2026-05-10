import 'package:curel/domain/providers/app_state.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

class SyncController {
  final Ref _ref;

  SyncController(this._ref);

  Future<void> syncAndRefresh() async {
    final ps = _ref.read(projectServiceProvider);
    final rs = _ref.read(requestServiceProvider);
    
    // 1. Rebuild project list from filesystem
    await ps.syncFromFilesystem();

    // 2. Fallback Active Project if missing
    var activeProject = await ps.getActiveProject();
    if (activeProject == null) {
      activeProject = await ps.ensureDefaultProject();
    }
    _ref.read(activeProjectProvider.notifier).set(activeProject);

    // 3. Fallback Selected Request if missing
    final selectedPath = _ref.read(selectedRequestPathProvider);
    if (selectedPath != null) {
      final requestsDir = await _ref.read(fileSystemProvider).getRequestsDir(activeProject.id);
      final exists = await _ref.read(fileSystemProvider).exists(
            p.join(requestsDir, selectedPath)
          );
      
      if (!exists) {
        _ref.read(selectedRequestPathProvider.notifier).state = null;
        
        // 4. Clear response output if the request is gone
        _ref.read(responseStateProvider.notifier).update((s) => s.copyWith(
          clearResponse: true,
          clearError: true,
        ));
      }
    }
    
    // Note: EnvService dynamically reads from disk on getActive(), 
    // so no manual memory sync is needed for environments.
  }
}
