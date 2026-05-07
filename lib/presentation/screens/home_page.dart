import 'dart:convert';

import 'package:curel/data/models/curl_response.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:curel/presentation/screens/about_page.dart';
import 'package:curel/presentation/screens/request_builder_page.dart';
import 'package:curel/data/services/curl_http_client.dart';
import 'package:curel/domain/services/clipboard_service.dart';
import 'package:curel/domain/services/curl_parser_service.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/help_sheet.dart';
import 'package:curel/presentation/widgets/response_viewer.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:curel/presentation/screens/settings_page.dart';
import 'package:curel/domain/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HomePage extends StatefulWidget {
  final CurlHttpClient httpClient;
  final ClipboardService clipboardService;
  final SettingsService settingsService;
  final void Function(String userAgent) onUserAgentChanged;

  const HomePage({
    required this.httpClient,
    required this.clipboardService,
    required this.settingsService,
    required this.onUserAgentChanged,
    super.key,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _curlController = _CurlHighlightController();
  final _focusNode = FocusNode();
  final _textFieldKey = GlobalKey();
  CurlResponse? _response;
  bool _isLoading = false;
  String? _error;
  var _selectedTab = ResponseTab.body;
  bool _showHtmlPreview = false;
  bool _searchActive = false;
  bool _isFullscreenInput = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && !_isFullscreenInput) {
        _enterFullscreen();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _curlController.dispose();
    super.dispose();
  }

  void _exitFullscreen() {
    _focusNode.unfocus();
    setState(() => _isFullscreenInput = false);
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
      _exitFullscreen();
      return;
    }

    setState(() {
      _isLoading = true;
      _response = null;
      _error = null;
      _showHtmlPreview = false;
    });
    _exitFullscreen();

    final sw = Stopwatch()..start();
    try {
      final parsed = parseCurl(text);
      final hasOutput = parsed.outputFileName != null;
      final traceEnabled = parsed.traceEnabled;
      final result = hasOutput
          ? await widget.httpClient.executeBinary(
              parsed.curl,
              verbose: parsed.verbose,
              followRedirects: parsed.followRedirects,
              trace: traceEnabled,
              traceAscii: parsed.traceAscii,
            )
          : await widget.httpClient.execute(
              parsed.curl,
              verbose: parsed.verbose,
              followRedirects: parsed.followRedirects,
              trace: traceEnabled,
              traceAscii: parsed.traceAscii,
            );
      final elapsed = sw.elapsedMilliseconds;
      if (elapsed < 500) {
        await Future.delayed(Duration(milliseconds: 500 - elapsed));
      }
      if (hasOutput) {
        if ((parsed.verbose || traceEnabled) && mounted) {
          setState(() {
            _response = result;
            if (traceEnabled && result.traceLog != null) {
              _selectedTab = ResponseTab.trace;
            }
          });
        }
        await _downloadFile(result, parsed.outputFileName!);
      } else if (mounted) {
        setState(() {
          _response = result;
          if (traceEnabled && result.traceLog != null) {
            _selectedTab = ResponseTab.trace;
          }
        });
      }
      if (parsed.traceFileName != null &&
          result.traceLog != null &&
          result.traceLog!.isNotEmpty &&
          mounted) {
        await _saveTraceFile(result.traceLog!, parsed.traceFileName!);
      }
    } catch (e) {
      final elapsed = sw.elapsedMilliseconds;
      if (elapsed < 500) {
        await Future.delayed(Duration(milliseconds: 500 - elapsed));
      }
      if (mounted) setState(() => _error = _formatError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _paste() async {
    final text = await widget.clipboardService.paste();
    if (text != null) {
      setState(() => _curlController.text = text);
      if (mounted) showTerminalToast(context, 'pasted from clipboard');
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

  Future<void> _saveResponse() async {
    if (_response == null) return;
    final rawExt = _response!.contentTypeLabel.toLowerCase();
    final ext = switch (rawExt) {
      'html' || 'json' || 'xml' || 'txt' || 'csv' => rawExt,
      _ => 'txt',
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
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save response',
        fileName: 'res-$ts.$ext',
        type: FileType.custom,
        allowedExtensions: [ext],
        bytes: utf8.encode(_response!.bodyText),
      );
      if (path != null && mounted) {
        showTerminalToast(context, 'saved');
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
      backgroundColor: TColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => HelpSheet(
        onUse: (command) {
          Navigator.of(context).pop();
          setState(() {
            _curlController.text = command;
            _response = null;
            _error = null;
          });
          _focusNode.requestFocus();
        },
      ),
    );
  }

  // ── Shared Builders ─────────────────────────────────────────────

  Widget _buildInputField({int? maxLines = 8, int minLines = 3}) {
    final unlimited = maxLines == null;
    Widget editor = Stack(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 0),
              child: Text(
                '❯ ',
                style: TextStyle(
                  color: TColors.green,
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: TextField(
                key: _textFieldKey,
                focusNode: _focusNode,
                controller: _curlController,
                maxLines: unlimited ? null : maxLines,
                minLines: minLines,
                cursorColor: TColors.green,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.4,
                  color: TColors.text,
                ),
                decoration: InputDecoration.collapsed(
                  hintText: 'paste or type a curl command...',
                  hintStyle: TextStyle(
                    color: TColors.mutedText.withValues(alpha: 0.5),
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
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
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.close, size: 12, color: TColors.red),
                ),
              );
            },
          ),
        ),
      ],
    );
    return SingleChildScrollView(
      physics: unlimited ? const ClampingScrollPhysics() : null,
      child: editor,
    );
  }

  Widget _buildActionButtons({bool fullscreen = false}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          TermButton(icon: Icons.science, onTap: _openBuilder),
          const SizedBox(width: 6),
          TermButton(
            icon: Icons.copy,
            onTap: () {
              final text = _curlController.text.trim();
              if (text.isNotEmpty) {
                Clipboard.setData(ClipboardData(text: text));
                showTerminalToast(context, 'copied to clipboard');
              }
            },
          ),
          const SizedBox(width: 6),
          TermButton(icon: Icons.content_paste, label: 'paste', onTap: _paste),
          const Spacer(),
          TermButton(
            icon: Icons.play_arrow,
            label: 'exec',
            onTap: _isLoading ? null : _executeCurl,
            accent: true,
          ),
          if (!fullscreen) ...[
            const SizedBox(width: 6),
            _MoreMenu(
              onAbout: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AboutPage())),
              onHelp: () => _showHelp(context),
              onSettings: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsPage(
                    settingsService: widget.settingsService,
                    onUserAgentChanged: widget.onUserAgentChanged,
                  ),
                ),
              ),
            ),
          ],
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
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
                            _response!.contentTypeLabel,
                            style: const TextStyle(
                              color: TColors.cyan,
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),

                          const SizedBox(width: 8),
                          _FlatTab(
                            label: 'headers',
                            selected: _selectedTab == ResponseTab.headers,
                            onTap: () => setState(() {
                              _selectedTab = ResponseTab.headers;
                              _showHtmlPreview = false;
                            }),
                          ),
                          const SizedBox(width: 8),
                          _FlatTab(
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
                            _FlatTab(
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
                            _FlatTab(
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
                    ),
                  ),
                  if (_response!.isHtml) ...[
                    GestureDetector(
                      onTap: () => setState(() {
                        _selectedTab = ResponseTab.body;
                        _showHtmlPreview = true;
                        _searchActive = false;
                      }),
                      child: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.visibility,
                          size: 16,
                          color: TColors.mutedText,
                        ),
                      ),
                    ),
                  ],
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(
                        ClipboardData(text: _response!.bodyText),
                      );
                      showTerminalToast(context, 'copied to clipboard');
                    },
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
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
                    onTap: () => setState(() => _searchActive = !_searchActive),
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
                  GestureDetector(
                    onTap: () => openFullscreenResponse(context, _response!),
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
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    _WindowDot(
                      color: TColors.red,
                      icon: Icons.close,
                      onTap: _exitFullscreen,
                    ),
                    const SizedBox(width: 6),
                    const _WindowDot(color: TColors.yellow),
                    const SizedBox(width: 6),
                    const _WindowDot(color: TColors.green),
                    const SizedBox(width: 12),
                    const Text(
                      'curl input',
                      style: TextStyle(
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
              Flexible(
                flex: 0,
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

            // Actions
            if (_isFullscreenInput) const Spacer(),
            _isFullscreenInput
                ? Container(
                    color: TColors.background,
                    child: _buildActionButtons(fullscreen: true),
                  )
                : _buildActionButtons(),

            // Response section (compact only)
            if (!_isFullscreenInput)
              Expanded(child: _buildResponseSection(isHorizontal: false)),
          ],
        ),
      ),
    );
  }

  void _enterFullscreen() {
    setState(() => _isFullscreenInput = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
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
                    onTap: () => _focusNode.requestFocus(),
                    child: Container(
                      color: TColors.surface,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: _buildInputField(maxLines: 12, minLines: 5),
                    ),
                  ),
                  _buildActionButtons(),
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
    r'''(curl)\b'''
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
        spans.add(TextSpan(
          text: m.group(1),
          style: const TextStyle(color: TColors.cyan, fontWeight: FontWeight.bold),
        ));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(
          text: m.group(2),
          style: const TextStyle(color: TColors.orange),
        ));
      } else if (m.group(4) != null) {
        spans.add(TextSpan(
          text: m.group(4),
          style: const TextStyle(color: TColors.yellow),
        ));
      } else if (m.group(5) != null) {
        spans.add(TextSpan(
          text: m.group(5),
          style: const TextStyle(color: TColors.yellow),
        ));
      } else if (m.group(6) != null) {
        spans.add(TextSpan(
          text: m.group(6),
          style: const TextStyle(color: TColors.green),
        ));
      } else if (m.group(7) != null) {
        final word = m.group(7)!;
        if (_methods.contains(word.toUpperCase())) {
          spans.add(TextSpan(
            text: word,
            style: const TextStyle(color: TColors.purple, fontWeight: FontWeight.bold),
          ));
        } else {
          spans.add(TextSpan(text: word));
        }
      } else if (m.group(8) != null) {
        spans.add(TextSpan(text: m.group(8)));
      }
    }

    return TextSpan(style: style, children: spans);
  }
}

// ── Flat Tab ──────────────────────────────────────────────────────

class _FlatTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FlatTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? TColors.green : Colors.transparent,
              width: 1,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            color: selected ? TColors.foreground : TColors.mutedText,
          ),
        ),
      ),
    );
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
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: TColors.mutedText, width: 1),
        ),
        child: const Center(
          child: Text(
            '?',
            style: TextStyle(
              color: TColors.mutedText,
              fontSize: 11,
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
  final VoidCallback onHelp;
  final VoidCallback onSettings;

  const _MoreMenu({
    required this.onAbout,
    required this.onHelp,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (details) {
        final renderBox = context.findRenderObject() as RenderBox;
        final offset = renderBox.localToGlobal(Offset.zero);
        showMenu<int>(
          context: context,
          position: RelativeRect.fromLTRB(
            offset.dx,
            offset.dy + renderBox.size.height,
            offset.dx + renderBox.size.width,
            0,
          ),
          color: TColors.surface,
          items: [
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
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        color: TColors.surface,
        child: Icon(Icons.more_vert, size: 14, color: TColors.mutedText),
      ),
    );
  }
}
