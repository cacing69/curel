import 'package:curel/data/models/curl_response.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/chunked_text_viewer.dart';
import 'package:curel/presentation/widgets/html_preview.dart';
import 'package:curel/presentation/widgets/searchable_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum ResponseTab { headers, body }

class ResponseViewer extends StatelessWidget {
  final CurlResponse? response;
  final String? error;
  final bool isLoading;
  final ResponseTab selectedTab;
  final bool showHtmlPreview;
  final bool searchActive;
  final VoidCallback? onCloseSearch;

  const ResponseViewer({
    this.isLoading = false,
    this.response,
    this.error,
    this.selectedTab = ResponseTab.body,
    this.showHtmlPreview = false,
    this.searchActive = false,
    this.onCloseSearch,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: _TerminalLoader());
    }

    if (error != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: SelectableText(
          error!,
          style: const TextStyle(
            color: TColors.error,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
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

      if (searchActive) {
        return SearchableText(
          text: response!.bodyText,
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

      return _buildHighlightedBody(response!);
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

  static Widget _buildHighlightedBody(CurlResponse response) {
    return ChunkedTextViewer(
      text: response.bodyText,
      language: response.highlightLanguage,
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
                    child: const Icon(Icons.arrow_back,
                        size: 18, color: TColors.mutedText),
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
                  const SizedBox(width: 4),
                  _FlatTab(
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
                    _FlatTab(
                      label: 'preview',
                      selected: _showHtmlPreview,
                      onTap: () => setState(() {
                        _selectedTab = ResponseTab.body;
                        _showHtmlPreview = true;
                        _searchActive = false;
                      }),
                    ),
                  ],
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: widget.response.bodyText));
                      showTerminalToast(
                        context,
                        'copied to clipboard',
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.copy, size: 16, color: TColors.mutedText),
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
                onCloseSearch: () => setState(() => _searchActive = false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
        final index = (_controller.value * _frames.length).floor() % _frames.length;
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
