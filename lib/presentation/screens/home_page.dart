import 'dart:convert';

import 'package:curel/data/models/curl_response.dart';
import 'package:curel/domain/models/history_model.dart';
import 'package:curel/domain/models/request_model.dart';
import 'package:curel/domain/providers/app_state.dart';
import 'package:curel/presentation/screens/project_list_page.dart';
import 'package:curel/presentation/widgets/action_toolbar.dart';
import 'package:curel/presentation/widgets/curl_highlight_controller.dart';
import 'package:curel/presentation/widgets/curl_input_field.dart';
import 'package:curel/presentation/widgets/editor_dashboard.dart';
import 'package:curel/presentation/widgets/env_bar.dart';
import 'package:curel/presentation/widgets/folder_chip.dart';
import 'package:curel/presentation/widgets/request_drawer.dart';
import 'package:curel/presentation/widgets/resolved_preview_dialog.dart';
import 'package:curel/presentation/widgets/response_section.dart';
import 'package:curel/presentation/widgets/window_controls.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:curel/presentation/screens/about_page.dart';
import 'package:curel/presentation/screens/feedback_page.dart';
import 'package:curel/presentation/screens/history_page.dart';
import 'package:curel/presentation/screens/request_builder_page.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:curel/domain/services/curl_parser_service.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/help_sheet.dart';
import 'package:curel/presentation/widgets/response_viewer.dart';
import 'package:curel/presentation/screens/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HomePage extends ConsumerStatefulWidget {
  final void Function(String userAgent) onUserAgentChanged;
  final void Function() onWorkspaceChanged;

  const HomePage({
    required this.onUserAgentChanged,
    required this.onWorkspaceChanged,
    super.key,
  });

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WidgetsBindingObserver {
  final _curlController = CurlHighlightController();
  final _editorFocusNode = FocusNode();
  final _textFieldKey = GlobalKey();
  OverlayEntry? _envOverlayEntry;
  List<String> _envOverlayOptions = const [];
  Offset _envOverlayOffset = Offset.zero;
  List<({String key, String lower})> _envKeyIndex = const [];

  String get _requestDisplayName {
    final path = ref.read(selectedRequestPathProvider);
    if (path == null) return '';
    final posix = path.replaceAll('\\', '/');
    return posix.replaceAll('.curl', '');
  }

  Future<void> _loadActiveProject() async {
    var project = await ref.read(projectServiceProvider).getActiveProject();
    project ??= await ref.read(projectServiceProvider).ensureDefaultProject();
    if (mounted) ref.read(activeProjectProvider.notifier).set(project);
    _refreshEnvKeys();
  }

  Future<void> _refreshEnvKeys() async {
    final keys = <String>{};
    final global = await ref.read(envServiceProvider).getActive(null);
    if (global != null) {
      keys.addAll(global.variables.map((v) => v.key));
    }
    final projectId = ref.read(activeProjectProvider)?.id;
    if (projectId != null) {
      final project = await ref.read(envServiceProvider).getActive(projectId);
      if (project != null) {
        keys.addAll(project.variables.map((v) => v.key));
      }
    }
    if (!mounted) return;
    final sorted = keys.toList()..sort();
    setState(() {
      _envKeyIndex = sorted
          .map((k) => (key: k, lower: k.toLowerCase()))
          .toList(growable: false);
    });
  }

  RenderEditable? _findRenderEditable(RenderObject root) {
    RenderEditable? result;
    void visitor(RenderObject child) {
      if (result != null) return;
      if (child is RenderEditable) {
        result = child;
        return;
      }
      child.visitChildren(visitor);
    }

    if (root is RenderEditable) return root;
    root.visitChildren(visitor);
    return result;
  }

  Offset _caretBottomInField({
    required GlobalKey fieldKey,
    required int caretOffset,
  }) {
    final fieldContext = fieldKey.currentContext;
    if (fieldContext == null) return Offset.zero;
    final fieldBox = fieldContext.findRenderObject() as RenderBox?;
    if (fieldBox == null) return Offset.zero;
    final root = fieldContext.findRenderObject();
    if (root == null) return Offset.zero;
    final renderEditable = _findRenderEditable(root);
    if (renderEditable == null) return Offset.zero;
    final caretRect = renderEditable.getLocalRectForCaret(
      TextPosition(offset: caretOffset),
    );
    final caretGlobal = renderEditable.localToGlobal(
      Offset(caretRect.left, caretRect.bottom),
    );
    return fieldBox.globalToLocal(caretGlobal);
  }

  ({int replaceStart, int replaceEnd, String query, bool hasClosing})?
  _envQueryAtCaret(TextEditingValue value) {
    final caret = value.selection.baseOffset;
    if (caret < 0) return null;
    final text = value.text;
    if (caret > text.length) return null;
    final before = text.substring(0, caret);
    final start = before.lastIndexOf('<<');
    if (start < 0) return null;
    if (before.indexOf('>>', start) != -1) return null;
    final query = before.substring(start + 2);
    if (query.isNotEmpty &&
        !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(query)) {
      return null;
    }
    final hasClosing = text.substring(caret).startsWith('>>');
    return (
      replaceStart: start + 2,
      replaceEnd: caret,
      query: query,
      hasClosing: hasClosing,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _editorFocusNode.addListener(_onEditorFocusChanged);
    _curlController.addListener(_onCurlValueChanged);
    _loadActiveProject();
    _checkClipboard();
    _refreshEnvKeys();
  }

  @override
  void dispose() {
    _hideEnvOverlay();
    WidgetsBinding.instance.removeObserver(this);
    _curlController.removeListener(_onCurlValueChanged);
    _editorFocusNode.removeListener(_onEditorFocusChanged);
    _editorFocusNode.dispose();
    _curlController.dispose();
    super.dispose();
  }

  void _onEditorFocusChanged() {
    if (!_editorFocusNode.hasFocus) {
      _hideEnvOverlay();
      return;
    }
    final es = ref.read(editorStateProvider);
    if (!es.isFullscreen) _enterFullscreen();
    _updateEnvOverlay();
  }

  void _onCurlValueChanged() {
    if (!_editorFocusNode.hasFocus) return;
    _updateEnvOverlay();
  }

  void _hideEnvOverlay() {
    _envOverlayEntry?.remove();
    _envOverlayEntry = null;
  }

  void _updateEnvOverlay() {
    if (!mounted) return;
    if (_envKeyIndex.isEmpty) {
      _hideEnvOverlay();
      return;
    }

    final value = _curlController.value;
    final q = _envQueryAtCaret(value);
    if (q == null) {
      _hideEnvOverlay();
      return;
    }

    final query = q.query.toLowerCase();
    final matches = _envKeyIndex
        .where((e) => query.isEmpty || e.lower.startsWith(query))
        .map((e) => e.key)
        .take(12)
        .toList(growable: false);
    if (matches.isEmpty) {
      _hideEnvOverlay();
      return;
    }

    final fieldContext = _textFieldKey.currentContext;
    if (fieldContext == null) return;
    final fieldBox = fieldContext.findRenderObject() as RenderBox?;
    if (fieldBox == null || !fieldBox.hasSize) return;

    final caret = value.selection.baseOffset;
    if (caret < 0 || caret > value.text.length) return;
    final caretLocal = _caretBottomInField(
      fieldKey: _textFieldKey,
      caretOffset: caret,
    );

    const menuMaxWidth = 220.0;
    const menuMaxHeight = 180.0;
    final fieldSize = fieldBox.size;

    final maxDx = (fieldSize.width - menuMaxWidth);
    final dx = (maxDx <= 0 ? 0.0 : caretLocal.dx.clamp(0.0, maxDx));

    var dy = caretLocal.dy + 4;
    if (dy + menuMaxHeight > fieldSize.height) {
      dy = (caretLocal.dy - menuMaxHeight - 4).clamp(0.0, fieldSize.height);
    }

    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;
    final globalTopLeft = fieldBox.localToGlobal(Offset(dx, dy));
    final overlayOffset = overlayBox.globalToLocal(globalTopLeft);

    _envOverlayOptions = matches;
    _envOverlayOffset = overlayOffset;

    if (_envOverlayEntry == null) {
      _envOverlayEntry = OverlayEntry(
        builder: (context) {
          final list = _envOverlayOptions;
          return Positioned(
            left: _envOverlayOffset.dx,
            top: _envOverlayOffset.dy,
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(
                  maxHeight: menuMaxHeight,
                  maxWidth: menuMaxWidth,
                ),
                decoration: BoxDecoration(
                  color: TColors.surface,
                  border: Border.all(color: TColors.border),
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final opt = list[index];
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        final current = _curlController.value;
                        final currentQ = _envQueryAtCaret(current);
                        if (currentQ == null) return;
                        final insert = opt + (currentQ.hasClosing ? '' : '>>');
                        final nextText = current.text.replaceRange(
                          currentQ.replaceStart,
                          currentQ.replaceEnd,
                          insert,
                        );
                        final nextCaret = currentQ.replaceStart + insert.length;
                        _curlController.value = current.copyWith(
                          text: nextText,
                          selection: TextSelection.collapsed(offset: nextCaret),
                          composing: TextRange.empty,
                        );
                        _hideEnvOverlay();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Text(
                          '<<$opt>>',
                          style: const TextStyle(
                            color: TColors.foreground,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
      overlay.insert(_envOverlayEntry!);
    } else {
      _envOverlayEntry!.markNeedsBuild();
    }
  }

  void _exitFullscreen({bool unfocus = true}) {
    if (unfocus) {
      _editorFocusNode.unfocus();
    }
    ref
        .read(editorStateProvider.notifier)
        .update((s) => s.copyWith(isFullscreen: false));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkClipboard();
    }
  }

  Future<void> _checkClipboard() async {
    final text = await ref.read(clipboardServiceProvider).paste();
    if (text != null && text.trim().startsWith('curl') && mounted) {
      if (_curlController.text.trim() != text.trim()) {
        _showClipboardDetection(text.trim());
      }
    }
  }

  void _showClipboardDetection(String curl) {
    showTerminalToast(
      context,
      'curl detected in clipboard',
      actionLabel: 'import',
      onAction: () {
        setState(() => _curlController.text = curl);
        ref
            .read(responseStateProvider.notifier)
            .update((s) => s.copyWith(clearResponse: true, clearError: true));
        showTerminalToast(context, 'imported');
      },
    );
  }

  // ── Actions ─────────────────────────────────────────────────────

  Future<void> _executeCurl() async {
    final text = _curlController.text.trim();
    if (text.isEmpty || !text.startsWith('curl')) {
      ref
          .read(responseStateProvider.notifier)
          .update(
            (s) => s.copyWith(
              clearResponse: true,
              error: 'error: command must start with "curl"',
              showHtmlPreview: false,
            ),
          );
      _exitFullscreen(unfocus: false);
      return;
    }

    ref
        .read(responseStateProvider.notifier)
        .update(
          (s) => s.copyWith(
            isLoading: true,
            clearResponse: true,
            clearError: true,
            showHtmlPreview: false,
          ),
        );
    final es = ref.read(editorStateProvider);
    if (es.isFullscreen) {
      ref
          .read(editorStateProvider.notifier)
          .update((s) => s.copyWith(isFullscreen: false));
    }
    await Future<void>.delayed(Duration.zero);

    final sw = Stopwatch()..start();
    try {
      final projectId = ref.read(activeProjectProvider)?.id;
      final shouldResolve = text.contains('<<');
      final resolved = shouldResolve
          ? await ref
                .read(envServiceProvider)
                .resolve(text, projectId: projectId)
          : text;
      final undefined = shouldResolve
          ? await ref
                .read(envServiceProvider)
                .findUndefinedVars(text, projectId: projectId)
          : const <String>{};
      if (undefined.isNotEmpty) {
        if (mounted) {
          showTerminalToast(context, 'undefined vars: ${undefined.join(', ')}');
          ref
              .read(responseStateProvider.notifier)
              .update(
                (s) => s.copyWith(
                  error: 'error: undefined vars: ${undefined.join(', ')}',
                ),
              );
        }
        return;
      }
      final parsed = parseCurl(resolved);
      final hasOutput = parsed.outputFileName != null;
      final traceEnabled = parsed.traceEnabled;
      final effectiveConnectTimeout =
          parsed.connectTimeout ??
          Duration(
            seconds: await ref.read(settingsProvider).getConnectTimeout(),
          );
      final effectiveMaxTime =
          parsed.maxTime ??
          ((await ref.read(settingsProvider).getMaxTime()) > 0
              ? Duration(seconds: await ref.read(settingsProvider).getMaxTime())
              : null);
      final result = hasOutput
          ? await ref
                .read(httpClientProvider)
                .executeBinary(
                  parsed.curl,
                  verbose: parsed.verbose,
                  followRedirects: parsed.followRedirects,
                  trace: traceEnabled,
                  traceAscii: parsed.traceAscii,
                  connectTimeout: effectiveConnectTimeout,
                  maxTime: effectiveMaxTime,
                  insecure: parsed.insecure,
                  httpVersion: parsed.httpVersion,
                )
          : await ref
                .read(httpClientProvider)
                .execute(
                  parsed.curl,
                  verbose: parsed.verbose,
                  followRedirects: parsed.followRedirects,
                  trace: traceEnabled,
                  traceAscii: parsed.traceAscii,
                  connectTimeout: effectiveConnectTimeout,
                  maxTime: effectiveMaxTime,
                  insecure: parsed.insecure,
                  httpVersion: parsed.httpVersion,
                );
      final elapsed = sw.elapsedMilliseconds;
      if (elapsed < 500) {
        await Future.delayed(Duration(milliseconds: 500 - elapsed));
      }
      final newTab = traceEnabled && result.traceLog != null
          ? ResponseTab.trace
          : ResponseTab.body;
      if (hasOutput) {
        if ((parsed.verbose || traceEnabled) && mounted) {
          ref
              .read(responseStateProvider.notifier)
              .update((s) => s.copyWith(response: result, selectedTab: newTab));
        }
        await _downloadFile(result, parsed.outputFileName!);
      } else if (mounted) {
        ref
            .read(responseStateProvider.notifier)
            .update((s) => s.copyWith(response: result, selectedTab: newTab));
      }
      if (parsed.traceFileName != null &&
          result.traceLog != null &&
          result.traceLog!.isNotEmpty &&
          mounted) {
        await _saveTraceFile(result.traceLog!, parsed.traceFileName!);
      }
      final projectId2 = ref.read(activeProjectProvider)?.id;
      final selectedPath = ref.read(selectedRequestPathProvider);
      if (projectId2 != null && selectedPath != null) {
        await ref
            .read(requestServiceProvider)
            .updateMeta(
              projectId2,
              selectedPath,
              RequestMeta(
                lastStatusCode: result.statusCode,
                lastRunAt: DateTime.now(),
              ),
            );
      }

      await ref
          .read(historyServiceProvider)
          .add(
            HistoryItem(
              timestamp: DateTime.now(),
              curlCommand: text,
              projectId: projectId,
              statusCode: result.statusCode,
              method: parsed.curl.method,
              url: parsed.curl.uri.toString(),
            ),
          );
    } catch (e) {
      final elapsed = sw.elapsedMilliseconds;
      if (elapsed < 500) {
        await Future.delayed(Duration(milliseconds: 500 - elapsed));
      }
      if (mounted) {
        final msg = _formatError(e);
        ref
            .read(responseStateProvider.notifier)
            .update((s) => s.copyWith(error: msg));
        showTerminalToast(context, msg);
      }
    } finally {
      if (mounted) {
        ref
            .read(responseStateProvider.notifier)
            .update((s) => s.copyWith(isLoading: false));
      }
    }
  }

  Future<void> _paste() async {
    final text = await ref.read(clipboardServiceProvider).paste();
    if (text != null && text.trim().isNotEmpty) {
      setState(() => _curlController.text = text);
      if (mounted) {
        showTerminalToast(context, 'pasted from clipboard', topOffset: 30);
      }
    }
  }

  void _clear() {
    _curlController.clear();
    ref
        .read(responseStateProvider.notifier)
        .update(
          (s) => s.copyWith(
            clearResponse: true,
            clearError: true,
            showHtmlPreview: false,
            searchActive: false,
          ),
        );
  }

  Future<void> _openBuilder() async {
    _exitFullscreen();
    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => RequestBuilderPage(
          projectId: ref.read(activeProjectProvider)?.id,
          initialCurl: _curlController.text.trim().isEmpty
              ? null
              : _curlController.text.trim(),
        ),
      ),
    );
    if (result != null && mounted) {
      if (result is String) {
        setState(() => _curlController.text = result);
        ref
            .read(responseStateProvider.notifier)
            .update(
              (s) => s.copyWith(
                clearResponse: true,
                clearError: true,
                showHtmlPreview: false,
                searchActive: false,
              ),
            );
        _executeCurl();
      } else if (result is CurlResponse) {
        ref
            .read(responseStateProvider.notifier)
            .update(
              (s) => s.copyWith(
                response: result,
                clearError: true,
                showHtmlPreview: false,
                searchActive: false,
              ),
            );
      }
    }
  }

  // ── Error formatting ─────────────────────────────────────────────

  String _formatError(Object e) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionError:
          return 'error: connection failed — host unreachable';
        case DioExceptionType.connectionTimeout:
          return 'error: connection timed out';
        case DioExceptionType.receiveTimeout:
          return 'error: response timed out';
        case DioExceptionType.unknown:
          return 'error: ${e.error}';
        default:
          return 'error: request failed (${e.type.name})';
      }
    }
    final msg = e.toString().replaceFirst(
      RegExp(r'^(Exception|FormatException|TypeError):\s*'),
      '',
    );
    return 'error: $msg';
  }

  // ── Download file (-o flag) ────────────────────────────────────────

  Future<void> _downloadFile(CurlResponse response, String fileName) async {
    try {
      final bytes = response.body is List<int>
          ? response.body as List<int>
          : utf8.encode(response.body?.toString() ?? '');
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save file',
        fileName: fileName,
        bytes: Uint8List.fromList(bytes),
      );
      if (path != null && mounted) {
        showTerminalToast(context, 'saved to $fileName');
      } else if (mounted) {
        showTerminalToast(context, 'download cancelled');
      }
    } catch (e) {
      if (mounted) showTerminalToast(context, 'error: $e');
    }
  }

  // ── Save trace file (--trace flag) ───────────────────────────────

  Future<void> _saveTraceFile(String traceContent, String fileName) async {
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save trace log',
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(traceContent)),
      );
      if (path != null && mounted) {
        showTerminalToast(context, 'trace saved to $fileName');
      }
    } catch (e) {
      if (mounted) showTerminalToast(context, 'error saving trace: $e');
    }
  }

  // ── Save response ────────────────────────────────────────────────

  ResponseTab get _activePreviewTab {
    final rs = ref.read(responseStateProvider);
    return rs.showHtmlPreview ? ResponseTab.body : rs.selectedTab;
  }

  String get _activePreviewTabLabel => switch (_activePreviewTab) {
    ResponseTab.headers => 'headers',
    ResponseTab.body => 'body',
    ResponseTab.verbose => 'verbose',
    ResponseTab.trace => 'trace',
  };

  String? _activePreviewText() {
    final rs = ref.read(responseStateProvider);
    final res = rs.response;
    if (res == null) return null;
    switch (_activePreviewTab) {
      case ResponseTab.headers:
        return res.formatHeaders();
      case ResponseTab.body:
        return res.getBodyText(rs.prettify);
      case ResponseTab.verbose:
        return res.formatVerboseLog();
      case ResponseTab.trace:
        return res.formatTraceLog();
    }
  }

  void _copyActivePreview() {
    final text = _activePreviewText()?.trim() ?? '';
    if (text.isEmpty) {
      showTerminalToast(context, '$_activePreviewTabLabel empty');
      return;
    }
    Clipboard.setData(ClipboardData(text: text));
    showTerminalToast(context, '$_activePreviewTabLabel copied');
  }

  Future<void> _saveResponse() async {
    final rs = ref.read(responseStateProvider);
    if (rs.response == null) return;
    final tab = _activePreviewTab;
    final text = _activePreviewText() ?? '';
    if (text.trim().isEmpty) {
      showTerminalToast(context, '$_activePreviewTabLabel empty');
      return;
    }

    final (dialogTitle, fileStem, ext) = switch (tab) {
      ResponseTab.headers => ('Save headers', 'headers', 'txt'),
      ResponseTab.body => () {
        final rawExt = rs.response!.contentTypeLabel.toLowerCase();
        final bodyExt = switch (rawExt) {
          'html' || 'json' || 'xml' || 'txt' || 'csv' => rawExt,
          _ => 'txt',
        };
        return ('Save response', 'res', bodyExt);
      }(),
      ResponseTab.verbose => ('Save verbose log', 'verbose', 'txt'),
      ResponseTab.trace => ('Save trace log', 'trace', 'txt'),
    };

    final now = DateTime.now();
    final ts =
        '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    try {
      final fileName = '$fileStem-$ts.$ext';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [ext],
        bytes: utf8.encode(text),
      );
      if (path != null && mounted) {
        showTerminalToast(context, '$_activePreviewTabLabel saved');
      }
    } catch (e) {
      if (mounted) showTerminalToast(context, 'error: $e');
    }
  }

  // ── Help ─────────────────────────────────────────────────────────

  void _showHelp(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: TColors.background,
      builder: (_) => HelpSheet(
        onUse: (command) {
          Navigator.of(context).pop();
          setState(() => _curlController.text = command);
          ref
              .read(responseStateProvider.notifier)
              .update((s) => s.copyWith(clearResponse: true, clearError: true));
          _editorFocusNode.requestFocus();
        },
      ),
    );
  }

  Future<void> _saveRequest() async {
    final projectId = ref.read(activeProjectProvider)?.id;
    final selectedPath = ref.read(selectedRequestPathProvider);
    if (projectId == null) {
      showTerminalToast(context, 'select a project first');
      return;
    }
    if (selectedPath == null) {
      _saveRequestAs();
      return;
    }
    final text = _curlController.text.trim();
    if (text.isEmpty) {
      showTerminalToast(context, 'nothing to save');
      return;
    }

    await ref
        .read(requestServiceProvider)
        .writeCurl(projectId, selectedPath, text);
    final rs = ref.read(responseStateProvider);
    if (rs.response != null) {
      await ref
          .read(requestServiceProvider)
          .updateMeta(
            projectId,
            selectedPath,
            RequestMeta(
              lastStatusCode: rs.response!.statusCode,
              lastRunAt: DateTime.now(),
            ),
          );
    }
    if (!mounted) return;
    ref
        .read(editorStateProvider.notifier)
        .update((s) => s.copyWith(baselineCurlText: _curlController.text));
    showTerminalToast(context, 'request saved');
  }

  Future<void> _saveRequestAs() async {
    final projectId = ref.read(activeProjectProvider)?.id;
    if (projectId == null) {
      showTerminalToast(context, 'select a project first');
      return;
    }
    final text = _curlController.text.trim();
    if (text.isEmpty) {
      showTerminalToast(context, 'nothing to save');
      return;
    }

    final selectedPath = ref.read(selectedRequestPathProvider);
    final name = await _showSaveDialog(
      initialName: selectedPath?.replaceAll('.curl', ''),
    );
    if (name == null || name.trim().isEmpty) return;
    final exists = await ref
        .read(requestServiceProvider)
        .requestExists(projectId, name.trim());
    if (exists && mounted) {
      final overwrite = await _showConfirmDialog(
        'overwrite?',
        '${name.trim()} already exists. overwrite?',
      );
      if (!mounted) return;
      if (overwrite != true) return;
      final relativePath = ref
          .read(requestServiceProvider)
          .resolvePath(name.trim());
      await ref
          .read(requestServiceProvider)
          .writeCurl(projectId, relativePath, text);
      final rs = ref.read(responseStateProvider);
      if (rs.response != null) {
        await ref
            .read(requestServiceProvider)
            .updateMeta(
              projectId,
              relativePath,
              RequestMeta(
                lastStatusCode: rs.response!.statusCode,
                lastRunAt: DateTime.now(),
              ),
            );
      }
      if (!mounted) return;
      ref.read(selectedRequestPathProvider.notifier).state = relativePath;
      ref
          .read(editorStateProvider.notifier)
          .update((s) => s.copyWith(baselineCurlText: _curlController.text));
      showTerminalToast(context, 'request saved');
    } else {
      final path = await ref
          .read(requestServiceProvider)
          .createRequest(projectId, name.trim(), text);
      final posix = name.trim().replaceAll('\\', '/');
      final slash = posix.lastIndexOf('/');
      final displayName = slash >= 0 ? posix.substring(slash + 1) : posix;
      await ref
          .read(requestServiceProvider)
          .updateMeta(projectId, path, RequestMeta(displayName: displayName));
      if (!mounted) return;
      ref.read(selectedRequestPathProvider.notifier).state = path;
      ref
          .read(editorStateProvider.notifier)
          .update((s) => s.copyWith(baselineCurlText: _curlController.text));
      showTerminalToast(context, 'request saved');
    }
  }

  void _newRequest() {
    Navigator.of(context).maybePop();
    setState(() => _curlController.clear());
    ref
        .read(editorStateProvider.notifier)
        .update((s) => s.copyWith(baselineCurlText: ''));
    ref
        .read(responseStateProvider.notifier)
        .update(
          (s) => s.copyWith(
            clearResponse: true,
            clearError: true,
            showHtmlPreview: false,
            searchActive: false,
          ),
        );
    ref.read(selectedRequestPathProvider.notifier).state = null;
    _editorFocusNode.requestFocus();
  }

  Future<void> _loadRequest(String relativePath) async {
    final projectId = ref.read(activeProjectProvider)?.id;
    final content = await ref
        .read(requestServiceProvider)
        .readCurl(projectId!, relativePath);
    if (content != null && mounted) {
      setState(() => _curlController.text = content);
      ref
          .read(editorStateProvider.notifier)
          .update((s) => s.copyWith(baselineCurlText: content));
      ref
          .read(responseStateProvider.notifier)
          .update(
            (s) => s.copyWith(
              clearResponse: true,
              clearError: true,
              showHtmlPreview: false,
              searchActive: false,
            ),
          );
      ref.read(selectedRequestPathProvider.notifier).state = relativePath;
      Navigator.of(context).maybePop();
    }
  }

  bool get _hasUnsavedChanges {
    final es = ref.read(editorStateProvider);
    return _curlController.text != es.baselineCurlText;
  }

  Future<int?> _confirmClose({required bool closingProject}) {
    final title = closingProject ? 'close project?' : 'close request?';
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TColors.surface,
        title: Text(
          title,
          style: const TextStyle(
            color: TColors.foreground,
            fontFamily: 'monospace',
            fontSize: 14,
          ),
        ),
        content: const Text(
          'you have unsaved changes. save before closing?',
          style: TextStyle(
            color: TColors.mutedText,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(0),
            child: const Text(
              'cancel',
              style: TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(1),
            child: const Text(
              'discard',
              style: TextStyle(color: TColors.red, fontFamily: 'monospace'),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(2),
            child: const Text(
              'save',
              style: TextStyle(color: TColors.green, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _closeRequest() async {
    final selectedPath = ref.read(selectedRequestPathProvider);
    if (_curlController.text.isEmpty && selectedPath == null) return;

    if (_hasUnsavedChanges) {
      final choice = await _confirmClose(closingProject: false);
      if (!mounted) return;
      if (choice == 0 || choice == null) return;
      if (choice == 2) {
        final es = ref.read(editorStateProvider);
        final before = es.baselineCurlText;
        if (selectedPath != null) {
          await _saveRequest();
        } else {
          await _saveRequestAs();
        }
        if (!mounted) return;
        final es2 = ref.read(editorStateProvider);
        if (es2.baselineCurlText == before) return;
      }
    }

    setState(() => _curlController.clear());
    ref
        .read(editorStateProvider.notifier)
        .update((s) => s.copyWith(baselineCurlText: ''));
    ref
        .read(responseStateProvider.notifier)
        .update(
          (s) => s.copyWith(
            clearResponse: true,
            clearError: true,
            showHtmlPreview: false,
            searchActive: false,
          ),
        );
    ref.read(selectedRequestPathProvider.notifier).state = null;
  }

  Future<void> _closeProject() async {
    final activeProject = ref.read(activeProjectProvider);
    if (activeProject == null) return;

    if (_curlController.text.isNotEmpty && _hasUnsavedChanges) {
      final choice = await _confirmClose(closingProject: true);
      if (!mounted) return;
      if (choice == 0 || choice == null) return;
      if (choice == 2) {
        final es = ref.read(editorStateProvider);
        final before = es.baselineCurlText;
        final selectedPath = ref.read(selectedRequestPathProvider);
        if (selectedPath != null) {
          await _saveRequest();
        } else {
          await _saveRequestAs();
        }
        if (!mounted) return;
        final es2 = ref.read(editorStateProvider);
        if (es2.baselineCurlText == before) return;
      }
    }

    await ref.read(projectServiceProvider).setActiveProject(null);
    if (!mounted) return;
    ref.read(activeProjectProvider.notifier).set(null);
    setState(() => _curlController.clear());
    ref
        .read(editorStateProvider.notifier)
        .update((s) => s.copyWith(baselineCurlText: ''));
    ref
        .read(responseStateProvider.notifier)
        .update(
          (s) => s.copyWith(
            clearResponse: true,
            clearError: true,
            showHtmlPreview: false,
            searchActive: false,
          ),
        );
    ref.read(selectedRequestPathProvider.notifier).state = null;
    _refreshEnvKeys();
  }

  Future<void> _openProjects() async {
    final projectId = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const ProjectListPage()));
    if (!mounted) return;
    if (projectId != null) {
      await _loadActiveProject();
      if (!mounted) return;
      setState(() => _curlController.clear());
      ref
          .read(editorStateProvider.notifier)
          .update((s) => s.copyWith(baselineCurlText: ''));
      ref
          .read(responseStateProvider.notifier)
          .update(
            (s) => s.copyWith(
              clearResponse: true,
              clearError: true,
              showHtmlPreview: false,
              searchActive: false,
            ),
          );
      ref.read(selectedRequestPathProvider.notifier).state = null;
    }
  }

  void _openRequestDrawer() {
    final projectId = ref.read(activeProjectProvider)?.id;
    if (projectId == null) {
      showTerminalToast(context, 'select a project first');
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: TColors.background,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.7,
        child: RequestDrawer(
          projectId: projectId,
          selectedPath: ref.read(selectedRequestPathProvider),
          onRequestSelected: _loadRequest,
          onNewRequest: _newRequest,
        ),
      ),
    );
  }

  Future<bool?> _showConfirmDialog(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TColors.surface,
        title: Text(
          title,
          style: TextStyle(
            color: TColors.foreground,
            fontFamily: 'monospace',
            fontSize: 14,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(
            color: TColors.mutedText,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'cancel',
              style: TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'overwrite',
              style: TextStyle(color: TColors.red, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _showSaveDialog({String? initialName}) async {
    final projectId = ref.read(activeProjectProvider)?.id;
    List<String> folders = [];
    if (projectId != null) {
      final items = await ref
          .read(requestServiceProvider)
          .listRequests(projectId);
      final folderSet = <String>{};
      for (final item in items) {
        final posix = item.relativePath.replaceAll('\\', '/');
        final slash = posix.lastIndexOf('/');
        if (slash >= 0) folderSet.add(posix.substring(0, slash));
      }
      folders = folderSet.toList()..sort();
    }
    if (!mounted) return null;

    final controller = TextEditingController(text: initialName ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TColors.surface,
        title: Text(
          'save request',
          style: TextStyle(
            color: TColors.foreground,
            fontFamily: 'monospace',
            fontSize: 14,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              cursorColor: TColors.green,
              style: TextStyle(
                color: TColors.foreground,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'folder/name (e.g. user/login)',
                hintStyle: TextStyle(
                  color: TColors.mutedText,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
                border: InputBorder.none,
                filled: true,
                fillColor: TColors.background,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
            if (folders.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'folders:',
                style: TextStyle(
                  color: TColors.mutedText,
                  fontFamily: 'monospace',
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  FolderChip(
                    label: '/ (root)',
                    onTap: () => controller.text = controller.text.contains('/')
                        ? controller.text
                        : controller.text,
                  ),
                  ...folders.map(
                    (f) => FolderChip(
                      label: f,
                      onTap: () {
                        final name = controller.text.split('/').last;
                        controller.text = '$f/${name.isEmpty ? '' : name}';
                      },
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'cancel',
              style: TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(
              'save',
              style: TextStyle(color: TColors.green, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared Builders ─────────────────────────────────────────────

  void _openResolvedPreview() {
    final text = _curlController.text.trim();
    if (text.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => ResolvedPreviewDialog(
        future: ref
            .read(envServiceProvider)
            .resolve(text, projectId: ref.read(activeProjectProvider)?.id),
      ),
    );
  }

  Widget _buildInputField({int? maxLines = 8, int minLines = 3}) {
    return CurlInputField(
      controller: _curlController,
      focusNode: _editorFocusNode,
      textFieldKey: _textFieldKey,
      onClear: _clear,
      maxLines: maxLines,
      minLines: minLines,
    );
  }

  Widget _buildEnvBar() {
    return EnvBar(
      requestDisplayName: _requestDisplayName,
      hasCurlText: _curlController.text.isNotEmpty,
      onOpenProjects: _openProjects,
      onOpenRequestDrawer: _openRequestDrawer,
      onCloseRequest: _closeRequest,
      onCloseProject: _closeProject,
      onSaveRequest: _saveRequest,
      onSaveRequestAs: _saveRequestAs,
      onEnvChanged: _refreshEnvKeys,
    );
  }

  Widget _buildActionToolbar() {
    final activeProject = ref.read(activeProjectProvider);
    return ActionToolbar(
      curlText: _curlController.text.trim(),
      onBuilder: _openBuilder,
      onPaste: _paste,
      onResolvedPreview: _openResolvedPreview,
      onExecute: _executeCurl,
      onHistorySelect: (curl) {
        setState(() => _curlController.text = curl);
        ref
            .read(responseStateProvider.notifier)
            .update((s) => s.copyWith(clearResponse: true, clearError: true));
      },
      onHelp: () => _showHelp(context),
      onNavigateAbout: (ctx) => Navigator.of(
        ctx,
      ).push(MaterialPageRoute(builder: (_) => const AboutPage())),
      onNavigateFeedback: (ctx) => Navigator.of(ctx).push(
        MaterialPageRoute(
          builder: (_) => FeedbackPage(
            projectId: ref.read(activeProjectProvider)?.id,
            projectName: activeProject?.name,
            requestPath: ref.read(selectedRequestPathProvider),
          ),
        ),
      ),
      onNavigateSettings: (ctx) => Navigator.of(ctx).push(
        MaterialPageRoute(
          builder: (_) => SettingsPage(
            onUserAgentChanged: widget.onUserAgentChanged,
            onWorkspaceChanged: widget.onWorkspaceChanged,
            projectId: ref.read(activeProjectProvider)?.id,
          ),
        ),
      ),
      onNavigateHistory: (ctx) => Navigator.of(ctx).push(
        MaterialPageRoute(
          builder: (_) => HistoryPage(
            currentProjectId: ref.read(activeProjectProvider)?.id,
            currentProjectName: activeProject?.name,
            onSelect: (curl) {
              setState(() => _curlController.text = curl);
              ref
                  .read(responseStateProvider.notifier)
                  .update(
                    (s) => s.copyWith(clearResponse: true, clearError: true),
                  );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildResponseSection({required bool isHorizontal}) {
    final rs = ref.read(responseStateProvider);
    return ResponseSection(
      isHorizontal: isHorizontal,
      onCopyActivePreview: _copyActivePreview,
      onSaveResponse: _saveResponse,
      onOpenFullscreen: () => openFullscreenResponse(context, rs.response!),
    );
  }

  // ── Layout Modes ────────────────────────────────────────────────

  Widget _buildPortraitLayout() {
    final es = ref.watch(editorStateProvider);
    final selectedPath = ref.watch(selectedRequestPathProvider);
    return Scaffold(
      backgroundColor: TColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (es.isFullscreen) ...[
              Container(
                color: TColors.surface,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                child: Row(
                  children: [
                    WindowDot(
                      color: TColors.red,
                      icon: Icons.close,
                      onTap: _exitFullscreen,
                    ),
                    const SizedBox(width: 4),
                    const WindowDot(color: TColors.yellow),
                    const SizedBox(width: 4),
                    const WindowDot(color: TColors.green),
                    const SizedBox(width: 10),
                    Text(
                      selectedPath != null
                          ? _requestDisplayName
                          : 'curl editor',
                      style: const TextStyle(
                        color: TColors.mutedText,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    HelpButton(onTap: () => _showHelp(context)),
                  ],
                ),
              ),
              Container(height: 1, color: TColors.border),
            ],

            if (es.isFullscreen)
              Expanded(
                child: Container(
                  color: TColors.surface,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: _buildInputField(maxLines: null, minLines: 1),
                ),
              )
            else
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _enterFullscreen,
                child: Container(
                  color: TColors.surface,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: _buildInputField(),
                ),
              ),

            EditorDashboard(
              envBar: _buildEnvBar(),
              actionBar: _buildActionToolbar(),
            ),

            if (!es.isFullscreen)
              Expanded(child: _buildResponseSection(isHorizontal: false)),
          ],
        ),
      ),
    );
  }

  void _enterFullscreen() {
    final es = ref.read(editorStateProvider);
    if (es.isFullscreen) return;
    ref
        .read(editorStateProvider.notifier)
        .update((s) => s.copyWith(isFullscreen: true));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editorFocusNode.requestFocus();
    });
  }

  Widget _buildHorizontalLayout() {
    return Scaffold(
      backgroundColor: TColors.background,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _editorFocusNode.requestFocus(),
                    child: Container(
                      color: TColors.surface,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [_buildInputField(maxLines: 12, minLines: 5)],
                      ),
                    ),
                  ),
                  EditorDashboard(
                    envBar: _buildEnvBar(),
                    actionBar: _buildActionToolbar(),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            Container(width: 1, color: TColors.border),
            Expanded(flex: 3, child: _buildResponseSection(isHorizontal: true)),
          ],
        ),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (isLandscape) return _buildHorizontalLayout();

    return _buildPortraitLayout();
  }
}
