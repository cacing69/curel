import 'package:curel/domain/adapters/collection_adapter.dart';
import 'package:curel/domain/adapters/internal/curel_native_adapter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AdapterRegistry {
  final List<CollectionAdapter> _adapters = [];

  AdapterRegistry() {
    // Register built-in adapters
    _register(CurelNativeAdapter());
    // Future: _register(PostmanAdapter());
  }

  void _register(CollectionAdapter adapter) {
    _adapters.add(adapter);
  }

  List<CollectionAdapter> get availableAdapters => List.unmodifiable(_adapters);

  CollectionAdapter? findAdapter(String content) {
    for (final adapter in _adapters) {
      if (adapter.canHandle(content)) return adapter;
    }
    return null;
  }
}

final adapterRegistryProvider = Provider((ref) => AdapterRegistry());
