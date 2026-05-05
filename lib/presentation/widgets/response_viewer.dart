import 'package:Curel/data/models/curl_response.dart';
import 'package:Curel/presentation/theme/terminal_colors.dart';
import 'package:Curel/presentation/widgets/html_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight2/themes/atom-one-dark.dart';
import 'package:flutter_highlight2/flutter_highlight.dart';

enum ResponseTab { headers, body }

class ResponseViewer extends StatelessWidget {
  final CurlResponse? response;
  final String? error;
  final bool isLoading;
  final ResponseTab selectedTab;
  final bool showHtmlPreview;

  const ResponseViewer({
    this.isLoading = false,
    this.response,
    this.error,
    this.selectedTab = ResponseTab.body,
    this.showHtmlPreview = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: TColors.green,
          ),
        ),
      );
    }

    if (error != null) {
      return SingleChildScrollView(
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
          child: SelectableText(
            response!.formatHeaders(),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: TColors.mutedText,
            ),
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
    final lang = response.highlightLanguage;

    if (lang != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: HighlightView(
          response.bodyText,
          language: lang,
          theme: atomOneDarkTheme,
          textStyle: const TextStyle(fontSize: 12),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: SelectableText(
        response.bodyText,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: TColors.text,
        ),
      ),
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
                      }),
                    ),
                  ],
                  const Spacer(),
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
                    '${widget.response.statusCode} ${widget.response.statusMessage}',
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
