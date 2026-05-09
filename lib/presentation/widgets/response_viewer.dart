import 'package:curel/data/models/curl_response.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:curel/presentation/widgets/chunked_text_viewer.dart';
import 'package:curel/presentation/widgets/html_preview.dart';
import 'package:curel/presentation/widgets/searchable_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum ResponseTab { headers, body, verbose, trace }

class ResponseViewer extends StatelessWidget {
  final CurlResponse? response;
  final String? error;
  final bool isLoading;
  final ResponseTab selectedTab;
  final bool showHtmlPreview;
  final bool searchActive;
  final bool prettify;
  final bool showLineNumbers;
  final VoidCallback? onCloseSearch;

  const ResponseViewer({
    this.isLoading = false,
    this.response,
    this.error,
    this.selectedTab = ResponseTab.body,
    this.showHtmlPreview = false,
    this.searchActive = false,
    this.prettify = true,
    this.showLineNumbers = false,
    this.onCloseSearch,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: _TerminalLoader());
    }

    if (error != null) {
      return Container(
        width: double.infinity,
        color: const Color(0xFF1E1E1E), // Darker background for error
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, size: 14, color: TColors.red),
                const SizedBox(width: 8),
                const Text(
                  'TERMINAL ERROR',
                  style: TextStyle(
                    color: TColors.red,
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(
              error!,
              style: const TextStyle(
                color: TColors.red,
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    if (response != null) {
      if (showHtmlPreview && response!.isHtml) {
        return HtmlPreview(html: response!.bodyText);
      }

      if (selectedTab == ResponseTab.headers) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: SelectionArea(
            child: RichText(
              text: response!.formatHeadersSpan(),
              softWrap: true,
            ),
          ),
        );
      }

      if (selectedTab == ResponseTab.verbose) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: SelectionArea(
            child: RichText(
              text: response!.formatVerboseLogSpan(),
              softWrap: true,
            ),
          ),
        );
      }

      if (selectedTab == ResponseTab.trace) {
        final lines = response!.traceLogLines;
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: lines.length,
          itemBuilder: (context, index) {
            return Text.rich(TextSpan(children: lines[index]));
          },
        );
      }

      if (searchActive) {
        return SearchableText(
          text: response!.getBodyText(prettify),
          searchActive: true,
          onClose: onCloseSearch,
          syntaxLanguage: response!.highlightLanguage,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: TColors.text,
          ),
        );
      }

      return _buildHighlightedBody(response!, prettify, showLineNumbers);
    }

    return Center(
      child: Text(
        'No response yet',
        style: TextStyle(
          color: TColors.mutedText.withValues(alpha: 0.5),
          fontSize: 12,
        ),
      ),
    );
  }

  static Widget _buildHighlightedBody(
    CurlResponse response,
    bool prettify,
    bool showLineNumbers,
  ) {
    return ChunkedTextViewer(
      text: response.getBodyText(prettify),
      language: response.highlightLanguage,
      showLineNumbers: showLineNumbers,
    );
  }
}

class FullscreenResponseViewer extends StatefulWidget {
  final CurlResponse response;

  const FullscreenResponseViewer({required this.response, super.key});

  @override
  State<FullscreenResponseViewer> createState() =>
      _FullscreenResponseViewerState();
}

class _FullscreenResponseViewerState extends State<FullscreenResponseViewer> {
  var _selectedTab = ResponseTab.body;
  bool _showHtmlPreview = false;
  bool _searchActive = false;
  bool _prettify = true;
  bool _showLineNumbers = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              color: TColors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(
                      Icons.arrow_back,
                      size: 18,
                      color: TColors.mutedText,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FlatTab(
                    label: 'headers',
                    selected: _selectedTab == ResponseTab.headers,
                    onTap: () => setState(() {
                      _selectedTab = ResponseTab.headers;
                      _showHtmlPreview = false;
                    }),
                  ),
                  const SizedBox(width: 4),
                  FlatTab(
                    label: 'body',
                    selected:
                        _selectedTab == ResponseTab.body && !_showHtmlPreview,
                    onTap: () => setState(() {
                      _selectedTab = ResponseTab.body;
                      _showHtmlPreview = false;
                    }),
                  ),
                  if (widget.response.isHtml) ...[
                    const SizedBox(width: 4),
                    FlatTab(
                      label: 'preview',
                      selected: _showHtmlPreview,
                      onTap: () => setState(() {
                        _selectedTab = ResponseTab.body;
                        _showHtmlPreview = true;
                        _searchActive = false;
                      }),
                    ),
                  ],
                  if (widget.response.traceLog != null &&
                      widget.response.traceLog!.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    FlatTab(
                      label: 'trace',
                      selected: _selectedTab == ResponseTab.trace,
                      onTap: () => setState(() {
                        _selectedTab = ResponseTab.trace;
                        _showHtmlPreview = false;
                        _searchActive = false;
                      }),
                    ),
                  ],
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(
                        ClipboardData(text: widget.response.bodyText),
                      );
                      showTerminalToast(context, 'copied to clipboard');
                    },
                    child: const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(
                        Icons.copy,
                        size: 16,
                        color: TColors.mutedText,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() {
                      _searchActive = !_searchActive;
                      if (_searchActive) _showHtmlPreview = false;
                    }),
                    child: Icon(
                      _searchActive ? Icons.search_off : Icons.search,
                      size: 16,
                      color: _searchActive ? TColors.green : TColors.mutedText,
                    ),
                  ),
                  if (widget.response.highlightLanguage == 'json') ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() => _prettify = !_prettify),
                      child: Icon(
                        _prettify ? Icons.auto_fix_high : Icons.auto_fix_off,
                        size: 16,
                        color: _prettify ? TColors.green : TColors.mutedText,
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () =>
                        setState(() => _showLineNumbers = !_showLineNumbers),
                    child: Icon(
                      Icons.format_list_numbered,
                      size: 16,
                      color: _showLineNumbers
                          ? TColors.green
                          : TColors.mutedText,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.response.contentTypeLabel,
                    style: const TextStyle(
                      color: TColors.cyan,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.response.timeLabel,
                    style: const TextStyle(
                      color: TColors.mutedText,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.response.bodySizeLabel,
                    style: const TextStyle(
                      color: TColors.mutedText,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.response.statusCode ?? '-'} ${widget.response.statusMessage}',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color:
                          (widget.response.statusCode ?? 0) >= 200 &&
                              (widget.response.statusCode ?? 0) < 300
                          ? TColors.green
                          : TColors.red,
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: TColors.border),
            Expanded(
              child: ResponseViewer(
                response: widget.response,
                selectedTab: _selectedTab,
                showHtmlPreview: _showHtmlPreview,
                searchActive: _searchActive,
                prettify: _prettify,
                showLineNumbers: _showLineNumbers,
                onCloseSearch: () => setState(() => _searchActive = false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void openFullscreenResponse(BuildContext context, CurlResponse response) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => FullscreenResponseViewer(response: response),
    ),
  );
}

class _TerminalLoader extends StatefulWidget {
  const _TerminalLoader();

  @override
  State<_TerminalLoader> createState() => _TerminalLoaderState();
}

class _TerminalLoaderState extends State<_TerminalLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _frames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final index =
            (_controller.value * _frames.length).floor() % _frames.length;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _frames[index],
              style: const TextStyle(
                color: TColors.green,
                fontFamily: 'monospace',
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'loading',
              style: TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ],
        );
      },
    );
  }
}
