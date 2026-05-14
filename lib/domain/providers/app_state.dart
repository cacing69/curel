import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:curel/data/models/curl_response.dart';
import 'package:curel/domain/models/project_model.dart';
import 'package:curel/presentation/widgets/response_toolbar.dart' show ResponseTab;

// ── Active Project ────────────────────────────────────────────────

class ActiveProjectNotifier extends Notifier<Project?> {
  @override
  Project? build() => null;

  void set(Project? project) => state = project;
}

final activeProjectProvider =
    NotifierProvider<ActiveProjectNotifier, Project?>(
  ActiveProjectNotifier.new,
);

// ── Response State ────────────────────────────────────────────────

class ResponseState {
  final CurlResponse? response;
  final bool isLoading;
  final String? error;
  final String? log;
  final ResponseTab selectedTab;
  final bool showHtmlPreview;
  final bool searchActive;
  final bool prettify;

  const ResponseState({
    this.response,
    this.isLoading = false,
    this.error,
    this.log,
    this.selectedTab = ResponseTab.body,
    this.showHtmlPreview = false,
    this.searchActive = false,
    this.prettify = true,
  });

  ResponseState copyWith({
    CurlResponse? response,
    bool? isLoading,
    String? error,
    String? log,
    ResponseTab? selectedTab,
    bool? showHtmlPreview,
    bool? searchActive,
    bool? prettify,
    bool clearError = false,
    bool clearLog = false,
    bool clearResponse = false,
  }) {
    return ResponseState(
      response: clearResponse ? null : (response ?? this.response),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      log: clearLog ? null : (log ?? this.log),
      selectedTab: selectedTab ?? this.selectedTab,
      showHtmlPreview: showHtmlPreview ?? this.showHtmlPreview,
      searchActive: searchActive ?? this.searchActive,
      prettify: prettify ?? this.prettify,
    );
  }
}

class ResponseStateNotifier extends Notifier<ResponseState> {
  @override
  ResponseState build() => const ResponseState();

  void update(ResponseState Function(ResponseState) fn) => state = fn(state);
}

final responseStateProvider =
    NotifierProvider<ResponseStateNotifier, ResponseState>(
  ResponseStateNotifier.new,
);

// ── Editor State ──────────────────────────────────────────────────

class EditorState {
  final bool isFullscreen;
  final String baselineCurlText;

  const EditorState({
    this.isFullscreen = false,
    this.baselineCurlText = '',
  });

  EditorState copyWith({
    bool? isFullscreen,
    String? baselineCurlText,
  }) {
    return EditorState(
      isFullscreen: isFullscreen ?? this.isFullscreen,
      baselineCurlText: baselineCurlText ?? this.baselineCurlText,
    );
  }
}

class EditorStateNotifier extends Notifier<EditorState> {
  @override
  EditorState build() => const EditorState();

  void update(EditorState Function(EditorState) fn) => state = fn(state);
}

final editorStateProvider =
    NotifierProvider<EditorStateNotifier, EditorState>(
  EditorStateNotifier.new,
);

// ── Selected Request ──────────────────────────────────────────────

final selectedRequestPathProvider = StateProvider<String?>((ref) => null);
