import 'dart:convert';

import 'package:curel/data/models/curl_response.dart';
import 'package:curel/domain/models/history_model.dart';
import 'package:curel/domain/models/project_model.dart';
import 'package:curel/domain/services/project_service.dart';
import 'package:curel/domain/models/request_model.dart';
import 'package:curel/domain/services/request_service.dart';
import 'package:curel/presentation/screens/project_list_page.dart';
import 'package:curel/presentation/widgets/request_drawer.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:curel/presentation/screens/about_page.dart';
import 'package:curel/presentation/screens/env_page.dart';
import 'package:curel/presentation/screens/feedback_page.dart';
import 'package:curel/presentation/screens/history_page.dart';
import 'package:curel/presentation/screens/request_builder_page.dart';
import 'package:curel/data/services/curl_http_client.dart';
import 'package:curel/data/services/filesystem_service.dart';
import 'package:curel/domain/services/env_service.dart';
import 'package:curel/domain/services/history_service.dart';
import 'package:curel/domain/services/bookmark_service.dart';
import 'package:curel/domain/services/clipboard_service.dart';
import 'package:curel/domain/services/curl_parser_service.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/help_sheet.dart';
import 'package:curel/presentation/widgets/response_viewer.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:curel/presentation/screens/settings_page.dart';
import 'package:curel/domain/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

class HomePage extends StatefulWidget {
  final CurlHttpClient httpClient;
  final ClipboardService clipboardService;
  final SettingsService settingsService;
  final EnvService envService;
  final ProjectService projectService;
  final RequestService requestService;
  final HistoryService historyService;
  final BookmarkService bookmarkService;
  final FileSystemService fsService;
  final void Function(String userAgent) onUserAgentChanged;
  final void Function() onWorkspaceChanged;

  const HomePage({
    required this.httpClient,
    required this.clipboardService,
    required this.settingsService,
    required this.envService,
    required this.projectService,
    required this.requestService,
    required this.historyService,
    required this.bookmarkService,
    required this.fsService,
    required this.onUserAgentChanged,
    required this.onWorkspaceChanged,
    super.key,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _curlController = _CurlHighlightController();
  final _editorFocusNode = FocusNode();
  final _textFieldKey = GlobalKey();
  OverlayEntry? _envOverlayEntry;
  List<String> _envOverlayOptions = const [];
  Offset _envOverlayOffset = Offset.zero;
  CurlResponse? _response;
  bool _isLoading = false;
  String? _error;
  var _selectedTab = ResponseTab.body;
  bool _showHtmlPreview = false;
  bool _searchActive = false;
  bool _prettify = true;
  bool _showLineNumbers = false;
  bool _isFullscreenInput = false;
  String _baselineCurlText = '';
  List<({String key, String lower})> _envKeyIndex = const [];
  TextEditingValue _lastEnvAutocompleteValue = const TextEditingValue();

  Project? _activeProject;
  String? _selectedRequestPath;

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

  String? get _projectId => _activeProject?.id;

  String get _requestDisplayName {
    if (_selectedRequestPath == null) return '';
    final posix = _selectedRequestPath!.replaceAll('\\', '/');
    return posix.replaceAll('.curl', '');
  }

  Future<void> _loadActiveProject() async {
    var project = await widget.projectService.getActiveProject();
    project ??= await widget.projectService.ensureDefaultProject();
    if (mounted) setState(() => _activeProject = project);
    _refreshEnvKeys();
  }

  Future<void> _refreshEnvKeys() async {
    final keys = <String>{};
    final global = await widget.envService.getActive(null);
    if (global != null) {
      keys.addAll(global.variables.map((v) => v.key));
    }
    if (_projectId != null) {
      final project = await widget.envService.getActive(_projectId);
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
    if (!_isFullscreenInput) _enterFullscreen();
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
    setState(() => _isFullscreenInput = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkClipboard();
    }
  }

  Future<void> _checkClipboard() async {
    final text = await widget.clipboardService.paste();
    if (text != null && text.trim().startsWith('curl') && mounted) {
      if (_curlController.text.trim() != text.trim()) {
        _showClipboardDetection(text.trim());
      }
    }
  }

  void _showClipboardDetection(String curl) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: TColors.surface,
        duration: const Duration(seconds: 5),
        content: Row(
          children: [
            Icon(Icons.content_paste, size: 14, color: TColors.green),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'curl detected in clipboard',
                style: TextStyle(
                  color: TColors.foreground,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'import',
          textColor: TColors.green,
          onPressed: () {
            setState(() {
              _curlController.text = curl;
              _response = null;
              _error = null;
            });
            showTerminalToast(context, 'imported');
          },
        ),
      ),
    );
  }

  // ── Actions ─────────────────────────────────────────────────────

  Future<void> _executeCurl() async {
    final text = _curlController.text.trim();
    if (text.isEmpty || !text.startsWith('curl')) {
      setState(() {
        _error = 'error: command must start with "curl"';
        _response = null;
        _showHtmlPreview = false;
      });
      _exitFullscreen(unfocus: false);
      return;
    }

    setState(() {
      _isLoading = true;
      _response = null;
      _error = null;
      _showHtmlPreview = false;
    });
    if (_isFullscreenInput) {
      setState(() => _isFullscreenInput = false);
    }
    await Future<void>.delayed(Duration.zero);

    final sw = Stopwatch()..start();
    try {
      final shouldResolve = text.contains('<<');
      final resolved = shouldResolve
          ? await widget.envService.resolve(text, projectId: _projectId)
          : text;
      final undefined = shouldResolve
          ? await widget.envService.findUndefinedVars(
              text,
              projectId: _projectId,
            )
          : const <String>{};
      if (undefined.isNotEmpty) {
        if (mounted) {
          showTerminalToast(context, 'undefined vars: ${undefined.join(', ')}');
          setState(
            () => _error = 'error: undefined vars: ${undefined.join(', ')}',
          );
        }
        return;
      }
      final parsed = parseCurl(resolved);
      final hasOutput = parsed.outputFileName != null;
      final traceEnabled = parsed.traceEnabled;
      final effectiveConnectTimeout =
          parsed.connectTimeout ??
          Duration(seconds: await widget.settingsService.getConnectTimeout());
      final effectiveMaxTime =
          parsed.maxTime ??
          ((await widget.settingsService.getMaxTime()) > 0
              ? Duration(seconds: await widget.settingsService.getMaxTime())
              : null);
      final result = hasOutput
          ? await widget.httpClient.executeBinary(
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
          : await widget.httpClient.execute(
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
      if (hasOutput) {
        if ((parsed.verbose || traceEnabled) && mounted) {
          setState(() {
            _response = result;
            _selectedTab = traceEnabled && result.traceLog != null
                ? ResponseTab.trace
                : ResponseTab.body;
          });
        }
        await _downloadFile(result, parsed.outputFileName!);
      } else if (mounted) {
        setState(() {
          _response = result;
          _selectedTab = traceEnabled && result.traceLog != null
              ? ResponseTab.trace
              : ResponseTab.body;
        });
      }
      if (parsed.traceFileName != null &&
          result.traceLog != null &&
          result.traceLog!.isNotEmpty &&
          mounted) {
        await _saveTraceFile(result.traceLog!, parsed.traceFileName!);
      }
      if (_projectId != null && _selectedRequestPath != null) {
        await widget.requestService.updateMeta(
          _projectId!,
          _selectedRequestPath!,
          RequestMeta(
            lastStatusCode: result.statusCode,
            lastRunAt: DateTime.now(),
          ),
        );
      }

      // Add to history
      await widget.historyService.add(
        HistoryItem(
          timestamp: DateTime.now(),
          curlCommand: text,
          projectId: _projectId,
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
        setState(() => _error = msg);
        showTerminalToast(context, msg);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _paste() async {
    final text = await widget.clipboardService.paste();
    if (text != null && text.trim().isNotEmpty) {
      setState(() => _curlController.text = text);
      if (mounted) {
        showTerminalToast(context, 'pasted from clipboard', topOffset: 30);
      }
    }
  }

  void _clear() {
    _curlController.clear();
    setState(() {
      _response = null;
      _error = null;
      _showHtmlPreview = false;
      _searchActive = false;
    });
  }

  Future<void> _openBuilder() async {
    _exitFullscreen();
    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => RequestBuilderPage(
          httpClient: widget.httpClient,
          envService: widget.envService,
          projectId: _projectId,
          initialCurl: _curlController.text.trim().isEmpty
              ? null
              : _curlController.text.trim(),
        ),
      ),
    );
    if (result != null && mounted) {
      if (result is String) {
        setState(() {
          _curlController.text = result;
          _response = null;
          _error = null;
          _showHtmlPreview = false;
          _searchActive = false;
        });
        _executeCurl();
      } else if (result is CurlResponse) {
        setState(() {
          _response = result;
          _error = null;
          _showHtmlPreview = false;
          _searchActive = false;
        });
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
    return 'error: $e';
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

  ResponseTab get _activePreviewTab =>
      _showHtmlPreview ? ResponseTab.body : _selectedTab;

  String get _activePreviewTabLabel => switch (_activePreviewTab) {
    ResponseTab.headers => 'headers',
    ResponseTab.body => 'body',
    ResponseTab.verbose => 'verbose',
    ResponseTab.trace => 'trace',
  };

  String? _activePreviewText() {
    final res = _response;
    if (res == null) return null;
    switch (_activePreviewTab) {
      case ResponseTab.headers:
        return res.formatHeaders();
      case ResponseTab.body:
        return res.getBodyText(_prettify);
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
    if (_response == null) return;
    final tab = _activePreviewTab;
    final text = _activePreviewText() ?? '';
    if (text.trim().isEmpty) {
      showTerminalToast(context, '$_activePreviewTabLabel empty');
      return;
    }

    final (dialogTitle, fileStem, ext) = switch (tab) {
      ResponseTab.headers => ('Save headers', 'headers', 'txt'),
      ResponseTab.body => () {
        final rawExt = _response!.contentTypeLabel.toLowerCase();
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
          setState(() {
            _curlController.text = command;
            _response = null;
            _error = null;
          });
          _editorFocusNode.requestFocus();
        },
      ),
    );
  }

  Future<void> _saveRequest() async {
    if (_projectId == null) {
      showTerminalToast(context, 'select a project first');
      return;
    }
    if (_selectedRequestPath == null) {
      _saveRequestAs();
      return;
    }
    final text = _curlController.text.trim();
    if (text.isEmpty) {
      showTerminalToast(context, 'nothing to save');
      return;
    }

    await widget.requestService.writeCurl(
      _projectId!,
      _selectedRequestPath!,
      text,
    );
    if (_response != null) {
      await widget.requestService.updateMeta(
        _projectId!,
        _selectedRequestPath!,
        RequestMeta(
          lastStatusCode: _response!.statusCode,
          lastRunAt: DateTime.now(),
        ),
      );
    }
    if (!mounted) return;
    _baselineCurlText = _curlController.text;
    showTerminalToast(context, 'request saved');
  }

  Future<void> _saveRequestAs() async {
    if (_projectId == null) {
      showTerminalToast(context, 'select a project first');
      return;
    }
    final text = _curlController.text.trim();
    if (text.isEmpty) {
      showTerminalToast(context, 'nothing to save');
      return;
    }

    final name = await _showSaveDialog(
      initialName: _selectedRequestPath?.replaceAll('.curl', ''),
    );
    if (name == null || name.trim().isEmpty) return;
    final exists = await widget.requestService.requestExists(
      _projectId!,
      name.trim(),
    );
    if (exists && mounted) {
      final overwrite = await _showConfirmDialog(
        'overwrite?',
        '${name.trim()} already exists. overwrite?',
      );
      if (!mounted) return;
      if (overwrite != true) return;
      final relativePath = widget.requestService.resolvePath(name.trim());
      await widget.requestService.writeCurl(_projectId!, relativePath, text);
      if (_response != null) {
        await widget.requestService.updateMeta(
          _projectId!,
          relativePath,
          RequestMeta(
            lastStatusCode: _response!.statusCode,
            lastRunAt: DateTime.now(),
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _selectedRequestPath = relativePath;
        _baselineCurlText = _curlController.text;
      });
      showTerminalToast(context, 'request saved');
    } else {
      final path = await widget.requestService.createRequest(
        _projectId!,
        name.trim(),
        text,
      );
      final posix = name.trim().replaceAll('\\', '/');
      final slash = posix.lastIndexOf('/');
      final displayName = slash >= 0 ? posix.substring(slash + 1) : posix;
      await widget.requestService.updateMeta(
        _projectId!,
        path,
        RequestMeta(displayName: displayName),
      );
      if (!mounted) return;
      setState(() {
        _selectedRequestPath = path;
        _baselineCurlText = _curlController.text;
      });
      showTerminalToast(context, 'request saved');
    }
  }

  void _newRequest() {
    Navigator.of(context).maybePop();
    setState(() {
      _curlController.clear();
      _baselineCurlText = '';
      _response = null;
      _error = null;
      _showHtmlPreview = false;
      _searchActive = false;
      _selectedRequestPath = null;
    });
    _editorFocusNode.requestFocus();
  }

  Future<void> _loadRequest(String relativePath) async {
    final content = await widget.requestService.readCurl(
      _projectId!,
      relativePath,
    );
    if (content != null && mounted) {
      setState(() {
        _curlController.text = content;
        _baselineCurlText = content;
        _response = null;
        _error = null;
        _showHtmlPreview = false;
        _searchActive = false;
        _selectedRequestPath = relativePath;
      });
      Navigator.of(context).maybePop();
    }
  }

  bool get _hasUnsavedChanges => _curlController.text != _baselineCurlText;

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
    if (_curlController.text.isEmpty && _selectedRequestPath == null) return;

    if (_hasUnsavedChanges) {
      final choice = await _confirmClose(closingProject: false);
      if (!mounted) return;
      if (choice == 0 || choice == null) return;
      if (choice == 2) {
        final before = _baselineCurlText;
        if (_selectedRequestPath != null) {
          await _saveRequest();
        } else {
          await _saveRequestAs();
        }
        if (!mounted) return;
        if (_baselineCurlText == before) return;
      }
    }

    setState(() {
      _curlController.clear();
      _baselineCurlText = '';
      _response = null;
      _error = null;
      _showHtmlPreview = false;
      _searchActive = false;
      _selectedRequestPath = null;
    });
  }

  Future<void> _closeProject() async {
    if (_activeProject == null) return;

    if (_curlController.text.isNotEmpty && _hasUnsavedChanges) {
      final choice = await _confirmClose(closingProject: true);
      if (!mounted) return;
      if (choice == 0 || choice == null) return;
      if (choice == 2) {
        final before = _baselineCurlText;
        if (_selectedRequestPath != null) {
          await _saveRequest();
        } else {
          await _saveRequestAs();
        }
        if (!mounted) return;
        if (_baselineCurlText == before) return;
      }
    }

    await widget.projectService.setActiveProject(null);
    if (!mounted) return;
    setState(() {
      _activeProject = null;
      _selectedRequestPath = null;
      _curlController.clear();
      _baselineCurlText = '';
      _response = null;
      _error = null;
      _showHtmlPreview = false;
      _searchActive = false;
    });
    _refreshEnvKeys();
  }

  Future<void> _openProjects() async {
    final projectId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ProjectListPage(
          projectService: widget.projectService,
          requestService: widget.requestService,
        ),
      ),
    );
    if (!mounted) return;
    if (projectId != null) {
      await _loadActiveProject();
      if (!mounted) return;
      setState(() {
        _selectedRequestPath = null;
        _curlController.clear();
        _baselineCurlText = '';
        _response = null;
        _error = null;
        _showHtmlPreview = false;
        _searchActive = false;
      });
    }
  }

  void _openRequestDrawer() {
    if (_projectId == null) {
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
          projectId: _projectId!,
          requestService: widget.requestService,
          selectedPath: _selectedRequestPath,
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
    List<String> folders = [];
    if (_projectId != null) {
      final items = await widget.requestService.listRequests(_projectId!);
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
                  _FolderChip(
                    label: '/ (root)',
                    onTap: () => controller.text = controller.text.contains('/')
                        ? controller.text
                        : controller.text,
                  ),
                  ...folders.map(
                    (f) => _FolderChip(
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

  void _openResolvedPreview() async {
    final text = _curlController.text.trim();
    if (text.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => _ResolvedPreviewDialog(
        future: widget.envService.resolve(text, projectId: _projectId),
      ),
    );
  }

  Widget _buildInputField({int? maxLines = 8, int minLines = 3}) {
    final unlimited = maxLines == null;
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '❯ ',
          style: TextStyle(
            color: TColors.green,
            fontFamily: 'monospace',
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        Expanded(
          child: TextField(
            key: _textFieldKey,
            focusNode: _editorFocusNode,
            controller: _curlController,
            maxLines: unlimited ? null : maxLines,
            minLines: unlimited ? null : minLines,
            expands: unlimited,
            cursorColor: TColors.green,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.4,
              color: TColors.text,
            ),
            decoration: const InputDecoration(
              hintText: 'paste or type a curl command...',
              hintStyle: TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.4,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    );
    return Stack(
      children: [
        if (unlimited) SizedBox.expand(child: content) else content,
        Positioned(
          top: 0,
          right: 0,
          child: ListenableBuilder(
            listenable: _curlController,
            builder: (context, _) {
              if (_curlController.text.isEmpty) {
                return const SizedBox.shrink();
              }
              return GestureDetector(
                onTap: _clear,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: TColors.surface,
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Icon(Icons.close, size: 12, color: TColors.red),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEnvBar() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: TColors.surface,
        border: Border(bottom: BorderSide(color: TColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.terminal, size: 12, color: TColors.green),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: _openProjects,
              behavior: HitTestBehavior.translucent,
              child: Row(
                children: [
                  Icon(
                    _activeProject == null
                        ? Icons.folder_open
                        : Icons.folder,
                    size: 14,
                    color: TColors.mutedText,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _activeProject?.name ?? 'no project',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _activeProject == null
                            ? TColors.mutedText
                            : TColors.orange,
                        fontFamily: 'monospace',
                        fontSize: 10,
                        fontWeight: _activeProject == null
                            ? FontWeight.normal
                            : FontWeight.bold,
                      ),
                    ),
                  ),
                  if (_activeProject != null) ...[
                    const Text(
                      ' › ',
                      style: TextStyle(
                        color: TColors.mutedText,
                        fontSize: 10,
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: _openRequestDrawer,
                        child: Text(
                          _selectedRequestPath != null
                              ? _requestDisplayName
                              : 'no request',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _selectedRequestPath != null
                                ? TColors.cyan
                                : TColors.mutedText,
                            fontFamily: 'monospace',
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_activeProject != null) ...[
            const SizedBox(width: 6),
            if (_selectedRequestPath != null || _curlController.text.isNotEmpty)
              GestureDetector(
                onTap: _closeRequest,
                child: const Icon(
                  Icons.close,
                  size: 14,
                  color: TColors.mutedText,
                ),
              ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _closeProject,
              child: const Icon(
                Icons.folder_off,
                size: 14,
                color: TColors.mutedText,
              ),
            ),
            if (_projectId != null) ...[
              if (_selectedRequestPath != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: _saveRequest,
                  child: const Icon(Icons.save, size: 14, color: TColors.green),
                ),
              ],
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _saveRequestAs,
                child: const Icon(
                  Icons.save_as,
                  size: 14,
                  color: TColors.mutedText,
                ),
              ),
            ],
          ],
          const SizedBox(width: 6),
          _EnvSwitch(
            envService: widget.envService,
            projectId: _projectId,
            onChanged: _refreshEnvKeys,
          ),
        ],
      ),
    );
  }

  Widget _buildActionToolbar() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Utilities Group
          _CompactIconButton(icon: Icons.science, onTap: _openBuilder),
          _CompactIconButton(
            icon: Icons.copy,
            onTap: () {
              final text = _curlController.text.trim();
              if (text.isNotEmpty) {
                Clipboard.setData(ClipboardData(text: text));
                showTerminalToast(context, 'copied');
              }
            },
          ),
          _CompactIconButton(icon: Icons.content_paste, onTap: _paste),
          _CompactIconButton(icon: Icons.code, onTap: _openResolvedPreview),

          const Spacer(),

          // System Group
          _MoreMenu(
            onAbout: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AboutPage())),
            onFeedback: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FeedbackPage(
                  projectId: _projectId,
                  projectName: _activeProject?.name,
                  requestPath: _selectedRequestPath,
                ),
              ),
            ),
            onHelp: () => _showHelp(context),
            onSettings: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SettingsPage(
                  settingsService: widget.settingsService,
                  envService: widget.envService,
                  fsService: widget.fsService,
                  onUserAgentChanged: widget.onUserAgentChanged,
                  onWorkspaceChanged: widget.onWorkspaceChanged,
                  projectId: _projectId,
                ),
              ),
            ),
            onHistory: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => HistoryPage(
                  historyService: widget.historyService,
                  bookmarkService: widget.bookmarkService,
                  currentProjectId: _projectId,
                  currentProjectName: _activeProject?.name,
                  onSelect: (curl) {
                    setState(() {
                      _curlController.text = curl;
                      _response = null;
                      _error = null;
                    });
                  },
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),
          // Execute Action
          TermButton(
            icon: Icons.play_arrow,
            label: 'exec',
            onTap: _isLoading ? null : _executeCurl,
            accent: true,
          ),
        ],
      ),
    );
  }

  Widget _buildResponseSection({required bool isHorizontal}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_response != null || _error != null) ...[
          Container(
            height: isHorizontal ? null : 1,
            width: isHorizontal ? 1 : null,
            color: TColors.border,
          ),
          if (_response != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text(
                        'res',
                        style: TextStyle(
                          color: TColors.purple,
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_response!.statusCode ?? '-'}',
                        style: TextStyle(
                          color:
                              (_response!.statusCode ?? 0) >= 200 &&
                                  (_response!.statusCode ?? 0) < 300
                              ? TColors.green
                              : TColors.red,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _response!.timeLabel,
                        style: const TextStyle(
                          color: TColors.mutedText,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _response!.bodySizeLabel,
                        style: const TextStyle(
                          color: TColors.mutedText,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _response!.contentTypeLabel,
                        style: const TextStyle(
                          color: TColors.cyan,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                      const Spacer(),
                      if (_response!.isHtml) ...[
                        GestureDetector(
                          onTap: () => setState(() {
                            _selectedTab = ResponseTab.body;
                            _showHtmlPreview = true;
                            _searchActive = false;
                          }),
                          child: const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.visibility,
                              size: 16,
                              color: TColors.mutedText,
                            ),
                          ),
                        ),
                      ],
                      GestureDetector(
                        onTap: _copyActivePreview,
                        child: const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.copy,
                            size: 16,
                            color: TColors.mutedText,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _saveResponse,
                        child: const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.save,
                            size: 16,
                            color: TColors.mutedText,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _searchActive = !_searchActive),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            _searchActive ? Icons.search_off : Icons.search,
                            size: 16,
                            color: _searchActive
                                ? TColors.green
                                : TColors.mutedText,
                          ),
                        ),
                      ),
                      if (_response?.highlightLanguage == 'json') ...[
                        GestureDetector(
                          onTap: () => setState(() => _prettify = !_prettify),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              _prettify
                                  ? Icons.auto_fix_high
                                  : Icons.auto_fix_off,
                              size: 16,
                              color: _prettify
                                  ? TColors.green
                                  : TColors.mutedText,
                            ),
                          ),
                        ),
                      ],
                      GestureDetector(
                        onTap: () => setState(
                          () => _showLineNumbers = !_showLineNumbers,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.format_list_numbered,
                            size: 16,
                            color: _showLineNumbers
                                ? TColors.green
                                : TColors.mutedText,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () =>
                            openFullscreenResponse(context, _response!),
                        child: const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.fullscreen,
                            size: 16,
                            color: TColors.mutedText,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      FlatTab(
                        label: 'headers',
                        selected: _selectedTab == ResponseTab.headers,
                        onTap: () => setState(() {
                          _selectedTab = ResponseTab.headers;
                          _showHtmlPreview = false;
                        }),
                      ),
                      const SizedBox(width: 8),
                      FlatTab(
                        label: 'body',
                        selected:
                            _selectedTab == ResponseTab.body &&
                            !_showHtmlPreview,
                        onTap: () => setState(() {
                          _selectedTab = ResponseTab.body;
                          _showHtmlPreview = false;
                        }),
                      ),
                      if (_response!.verboseLog != null &&
                          _response!.verboseLog!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        FlatTab(
                          label: 'verbose',
                          selected: _selectedTab == ResponseTab.verbose,
                          onTap: () => setState(() {
                            _selectedTab = ResponseTab.verbose;
                            _showHtmlPreview = false;
                          }),
                        ),
                      ],
                      if (_response!.traceLog != null &&
                          _response!.traceLog!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        FlatTab(
                          label: 'trace',
                          selected: _selectedTab == ResponseTab.trace,
                          onTap: () => setState(() {
                            _selectedTab = ResponseTab.trace;
                            _showHtmlPreview = false;
                          }),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          Container(
            height: isHorizontal ? null : 1,
            width: isHorizontal ? 1 : null,
            color: TColors.border,
          ),
        ],
        Expanded(
          child: ResponseViewer(
            isLoading: _isLoading,
            response: _response,
            error: _error,
            selectedTab: _selectedTab,
            showHtmlPreview: _showHtmlPreview,
            searchActive: _searchActive,
            prettify: _prettify,
            showLineNumbers: _showLineNumbers,
            onCloseSearch: () => setState(() => _searchActive = false),
          ),
        ),
      ],
    );
  }

  // ── Layout Modes ────────────────────────────────────────────────

  Widget _buildPortraitLayout() {
    return Scaffold(
      backgroundColor: TColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fullscreen header
            if (_isFullscreenInput) ...[
              Container(
                color: TColors.surface,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                child: Row(
                  children: [
                    _WindowDot(
                      color: TColors.red,
                      icon: Icons.close,
                      onTap: _exitFullscreen,
                    ),
                    const SizedBox(width: 4),
                    const _WindowDot(color: TColors.yellow),
                    const SizedBox(width: 4),
                    const _WindowDot(color: TColors.green),
                    const SizedBox(width: 10),
                    Text(
                      _selectedRequestPath != null
                          ? _requestDisplayName
                          : 'curl editor',
                      style: const TextStyle(
                        color: TColors.mutedText,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    _HelpButton(onTap: () => _showHelp(context)),
                  ],
                ),
              ),
              Container(height: 1, color: TColors.border),
            ],

            // Input area
            if (_isFullscreenInput)
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

            // Dashboard (Controls)
            if (_isFullscreenInput)
              _EditorDashboard(
                envBar: _buildEnvBar(),
                actionBar: _buildActionToolbar(),
              )
            else
              _EditorDashboard(
                envBar: _buildEnvBar(),
                actionBar: _buildActionToolbar(),
              ),

            // Response section (compact only)
            if (!_isFullscreenInput)
              Expanded(child: _buildResponseSection(isHorizontal: false)),
          ],
        ),
      ),
    );
  }

  void _enterFullscreen() {
    if (_isFullscreenInput) return;
    setState(() => _isFullscreenInput = true);
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
            // Left: Input panel
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
                  _EditorDashboard(
                    envBar: _buildEnvBar(),
                    actionBar: _buildActionToolbar(),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            // Divider
            Container(width: 1, color: TColors.border),
            // Right: Output panel
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

// ── Curl Syntax Highlighter ───────────────────────────────────────

class _CurlHighlightController extends TextEditingController {
  static const _methods = {
    'GET',
    'POST',
    'PUT',
    'DELETE',
    'PATCH',
    'HEAD',
    'OPTIONS',
  };

  static final _tokenRegex = RegExp(
    r'(<<[A-Za-z_][A-Za-z0-9_]*>>)'
    r'''|(curl)\b'''
    r'|(-(-?[A-Za-z][\w-]*))'
    r"""|('[^']*')"""
    r'''|("[^"]*")'''
    r'''|(https?://[^\s'"]+)'''
    r'|(\S+)'
    r'|(\s+)',
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (text.isEmpty) {
      return TextSpan(style: style, text: '');
    }

    final spans = <TextSpan>[];

    for (final m in _tokenRegex.allMatches(text)) {
      if (m.group(1) != null) {
        spans.add(
          TextSpan(
            text: m.group(1),
            style: const TextStyle(color: TColors.purple),
          ),
        );
      } else if (m.group(2) != null) {
        spans.add(
          TextSpan(
            text: m.group(2),
            style: const TextStyle(
              color: TColors.cyan,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      } else if (m.group(3) != null) {
        spans.add(
          TextSpan(
            text: m.group(3),
            style: const TextStyle(color: TColors.orange),
          ),
        );
      } else if (m.group(5) != null) {
        spans.add(
          TextSpan(
            text: m.group(5),
            style: const TextStyle(color: TColors.yellow),
          ),
        );
      } else if (m.group(6) != null) {
        spans.add(
          TextSpan(
            text: m.group(6),
            style: const TextStyle(color: TColors.yellow),
          ),
        );
      } else if (m.group(7) != null) {
        spans.add(
          TextSpan(
            text: m.group(7),
            style: const TextStyle(color: TColors.green),
          ),
        );
      } else if (m.group(8) != null) {
        final word = m.group(8)!;
        if (_methods.contains(word.toUpperCase())) {
          spans.add(
            TextSpan(
              text: word,
              style: const TextStyle(
                color: TColors.purple,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        } else {
          spans.add(TextSpan(text: word));
        }
      } else if (m.group(9) != null) {
        spans.add(TextSpan(text: m.group(9)));
      }
    }

    return TextSpan(style: style, children: spans);
  }
}

class _HelpButton extends StatelessWidget {
  final VoidCallback onTap;

  const _HelpButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: TColors.mutedText, width: 1),
        ),
        child: const Center(
          child: Text(
            '?',
            style: TextStyle(
              color: TColors.mutedText,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowDot extends StatelessWidget {
  final Color color;
  final IconData? icon;
  final VoidCallback? onTap;

  const _WindowDot({required this.color, this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: icon != null
            ? Icon(icon, size: 8, color: TColors.background)
            : null,
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  final VoidCallback onAbout;
  final VoidCallback onFeedback;
  final VoidCallback onHelp;
  final VoidCallback onSettings;
  final VoidCallback onHistory;

  const _MoreMenu({
    required this.onAbout,
    required this.onFeedback,
    required this.onHelp,
    required this.onSettings,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (details) {
        final renderBox = context.findRenderObject() as RenderBox;
        final offset = renderBox.localToGlobal(Offset.zero);
        showMenu<int>(
          context: context,
          elevation: 0,
          position: RelativeRect.fromLTRB(
            offset.dx,
            offset.dy + renderBox.size.height,
            offset.dx + renderBox.size.width,
            0,
          ),
          color: TColors.surface,
          items: [
            PopupMenuItem<int>(
              value: 3,
              height: 36,
              child: Row(
                children: [
                  const Icon(Icons.history, size: 14, color: TColors.mutedText),
                  const SizedBox(width: 8),
                  const Text(
                    'history',
                    style: TextStyle(
                      color: TColors.foreground,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem<int>(
              value: 4,
              height: 36,
              child: Row(
                children: [
                  const Icon(
                    Icons.chat_bubble_outline,
                    size: 14,
                    color: TColors.mutedText,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'feedback',
                    style: TextStyle(
                      color: TColors.foreground,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem<int>(
              value: 0,
              height: 36,
              child: Row(
                children: [
                  Icon(
                    Icons.settings_outlined,
                    size: 14,
                    color: TColors.mutedText,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'settings',
                    style: TextStyle(
                      color: TColors.foreground,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem<int>(
              value: 1,
              height: 36,
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: TColors.mutedText),
                  const SizedBox(width: 8),
                  Text(
                    'about',
                    style: TextStyle(
                      color: TColors.foreground,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem<int>(
              value: 2,
              height: 36,
              child: Row(
                children: [
                  Icon(Icons.help_outline, size: 14, color: TColors.mutedText),
                  const SizedBox(width: 8),
                  Text(
                    'help',
                    style: TextStyle(
                      color: TColors.foreground,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ).then((value) {
          if (value == 0) onSettings();
          if (value == 1) onAbout();
          if (value == 2) onHelp();
          if (value == 3) onHistory();
          if (value == 4) onFeedback();
        });
      },
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        color: TColors.surface,
        child: Icon(Icons.more_vert, size: 14, color: TColors.mutedText),
      ),
    );
  }
}

class _EnvSwitch extends StatefulWidget {
  final EnvService envService;
  final String? projectId;
  final VoidCallback? onChanged;

  const _EnvSwitch({required this.envService, this.projectId, this.onChanged});

  @override
  State<_EnvSwitch> createState() => _EnvSwitchState();
}

class _EnvSwitchState extends State<_EnvSwitch> {
  String? _activeName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final active = await widget.envService.getActive(widget.projectId);
    if (mounted) setState(() => _activeName = active?.name);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (details) async {
        final envs = await widget.envService.getAll(widget.projectId);
        if (!mounted) return;
        final active = await widget.envService.getActive(widget.projectId);
        if (!mounted) return;
        final renderBox = this.context.findRenderObject() as RenderBox;
        final offset = renderBox.localToGlobal(Offset.zero);
        showMenu<String>(
          context: this.context,
          elevation: 0,
          constraints: const BoxConstraints(maxWidth: 180),
          position: RelativeRect.fromLTRB(
            offset.dx,
            offset.dy + renderBox.size.height,
            offset.dx + renderBox.size.width,
            0,
          ),
          color: TColors.surface,
          items: [
            ...envs.map(
              (e) => PopupMenuItem<String>(
                value: e.id,
                height: 36,
                child: Row(
                  children: [
                    Icon(
                      e.id == active?.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 14,
                      color: e.id == active?.id
                          ? TColors.green
                          : TColors.mutedText,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: e.id == active?.id
                              ? TColors.green
                              : TColors.foreground,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            PopupMenuItem<String>(
              value: 'manage',
              height: 36,
              child: Row(
                children: [
                  Icon(Icons.widgets, size: 14, color: TColors.mutedText),
                  const SizedBox(width: 8),
                  Text(
                    'env',
                    style: TextStyle(
                      color: TColors.foreground,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ).then((value) async {
          if (value == null) return;
          if (!mounted) return;
          if (value == 'manage') {
            Navigator.of(this.context)
                .push(
                  MaterialPageRoute(
                    builder: (_) => EnvPage(
                      envService: widget.envService,
                      projectId: widget.projectId,
                    ),
                  ),
                )
                .then((_) {
                  _load();
                  widget.onChanged?.call();
                });
          } else {
            await widget.envService.setActive(widget.projectId, value);
            _load();
            widget.onChanged?.call();
          }
        });
      },
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        color: TColors.surface,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.data_object, size: 14, color: TColors.cyan),
            if (_activeName != null) ...[
              const SizedBox(width: 4),
              Text(
                _activeName!.length > 6
                    ? '${_activeName!.substring(0, 4)}…'
                    : _activeName!,
                style: const TextStyle(
                  color: TColors.cyan,
                  fontFamily: 'monospace',
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EditorDashboard extends StatelessWidget {
  final Widget envBar;
  final Widget actionBar;

  const _EditorDashboard({required this.envBar, required this.actionBar});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: TColors.background,
        border: Border(
          top: BorderSide(color: TColors.border, width: 1),
          bottom: BorderSide(color: TColors.border, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [envBar, actionBar],
      ),
    );
  }
}

class _CompactIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _CompactIconButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      color: TColors.mutedText,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(),
      splashRadius: 20,
    );
  }
}

class _FolderChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _FolderChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: TColors.background,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder, size: 10, color: TColors.orange),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: TColors.orange,
                fontFamily: 'monospace',
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResolvedPreviewDialog extends StatelessWidget {
  final Future<String> future;

  const _ResolvedPreviewDialog({required this.future});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: TColors.background,
      insetPadding: EdgeInsets.zero,
      alignment: Alignment.centerLeft,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              color: TColors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Text(
                    'resolved command',
                    style: TextStyle(
                      color: TColors.purple,
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: TColors.mutedText,
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: TColors.border),
            Expanded(
              child: FutureBuilder<String>(
                future: future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: TColors.green,
                        strokeWidth: 2,
                      ),
                    );
                  }
                  final text = snapshot.data ?? '';
                  final lines = _splitToHighlightLines(text);
                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: lines.length,
                    itemBuilder: (context, index) {
                      return Text.rich(
                        TextSpan(
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.5,
                          ),
                          children: lines[index],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static List<List<TextSpan>> _splitToHighlightLines(String text) {
    final allSpans = <TextSpan>[];
    for (final m in _CurlHighlightController._tokenRegex.allMatches(text)) {
      if (m.group(1) != null) {
        allSpans.add(
          TextSpan(
            text: m.group(1),
            style: const TextStyle(color: TColors.purple),
          ),
        );
      } else if (m.group(2) != null) {
        allSpans.add(
          TextSpan(
            text: m.group(2),
            style: const TextStyle(
              color: TColors.cyan,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      } else if (m.group(3) != null) {
        allSpans.add(
          TextSpan(
            text: m.group(3),
            style: const TextStyle(color: TColors.orange),
          ),
        );
      } else if (m.group(5) != null) {
        allSpans.add(
          TextSpan(
            text: m.group(5),
            style: const TextStyle(color: TColors.yellow),
          ),
        );
      } else if (m.group(6) != null) {
        allSpans.add(
          TextSpan(
            text: m.group(6),
            style: const TextStyle(color: TColors.yellow),
          ),
        );
      } else if (m.group(7) != null) {
        allSpans.add(
          TextSpan(
            text: m.group(7),
            style: const TextStyle(color: TColors.green),
          ),
        );
      } else if (m.group(8) != null) {
        final word = m.group(8)!;
        if (_CurlHighlightController._methods.contains(word.toUpperCase())) {
          allSpans.add(
            TextSpan(
              text: word,
              style: const TextStyle(
                color: TColors.purple,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        } else {
          allSpans.add(TextSpan(text: word));
        }
      } else if (m.group(9) != null) {
        allSpans.add(TextSpan(text: m.group(9)));
      }
    }

    final lines = <List<TextSpan>>[[]];
    for (final span in allSpans) {
      final spanText = span.text ?? '';
      if (!spanText.contains('\n')) {
        lines.last.add(span);
        continue;
      }
      final parts = spanText.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) lines.add([]);
        if (parts[i].isNotEmpty) {
          lines.last.add(TextSpan(text: parts[i], style: span.style));
        }
      }
    }
    return lines;
  }
}
