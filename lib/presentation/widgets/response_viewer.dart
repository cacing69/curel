import 'package:curel/data/models/curl_response.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:curel/presentation/widgets/chunked_text_viewer.dart';
import 'package:curel/presentation/widgets/html_preview.dart';
import 'package:curel/presentation/widgets/searchable_text.dart';
import 'package:curel/presentation/widgets/diff_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum ResponseTab { headers, body, verbose, trace }

class ResponseViewer extends StatelessWidget {
  final CurlResponse? response;
  final String? error;
  final String? log;
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
    this.log,
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
      return const Center(child: TerminalLoader());
    }

    if (error != null) {
      return Container(
        width: double.infinity,
        color: Color(0xFF1E1E1E), // Darker background for error
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, size: 14, color: TColors.red),
                SizedBox(width: 8),
                Text(
                  'terminal error',
                  style: TextStyle(
                    color: TColors.red,
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Builder(
                  builder: (context) => GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: error!));
                      showTerminalToast(context, 'copied');
                    },
                    child: Icon(Icons.copy, size: 14, color: TColors.mutedText),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            SelectableText(
              error!,
              style: TextStyle(
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

    if (log != null) {
      return Container(
        width: double.infinity,
        color: Color(0xFF1E1E1E),
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sync, size: 14, color: TColors.cyan),
                SizedBox(width: 8),
                Text(
                  'sync log',
                  style: TextStyle(
                    color: TColors.cyan,
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Builder(
                  builder: (context) => GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: log!));
                      showTerminalToast(context, 'copied');
                    },
                    child: Icon(Icons.copy, size: 14, color: TColors.mutedText),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            SelectableText(
              log!,
              style: TextStyle(
                color: TColors.foreground,
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
          padding: EdgeInsets.all(8),
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
          padding: EdgeInsets.all(8),
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
          padding: EdgeInsets.all(8),
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
          style: TextStyle(
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
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Icon(
                          Icons.arrow_back,
                          size: 18,
                          color: TColors.mutedText,
                        ),
                      ),
                      SizedBox(width: 8),
                      FlatTab(
                        label: 'headers',
                        selected: _selectedTab == ResponseTab.headers,
                        onTap: () => setState(() {
                          _selectedTab = ResponseTab.headers;
                          _showHtmlPreview = false;
                        }),
                      ),
                      SizedBox(width: 4),
                      FlatTab(
                        label: 'body',
                        selected: _selectedTab == ResponseTab.body && !_showHtmlPreview,
                        onTap: () => setState(() {
                          _selectedTab = ResponseTab.body;
                          _showHtmlPreview = false;
                        }),
                      ),
                      if (widget.response.isHtml) ...[
                        SizedBox(width: 4),
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
                        SizedBox(width: 4),
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
                    ],
                  ),
                  SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(text: widget.response.bodyText),
                            );
                            showTerminalToast(context, 'copied to clipboard');
                          },
                          child: Padding(
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
                          SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => setState(() => _prettify = !_prettify),
                            child: Icon(
                              _prettify ? Icons.auto_fix_high : Icons.auto_fix_off,
                              size: 16,
                              color: _prettify ? TColors.green : TColors.mutedText,
                            ),
                          ),
                        ],
                        SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _openCompareDialog(context),
                          child: Icon(
                            Icons.compare_arrows,
                            size: 16,
                            color: TColors.mutedText,
                          ),
                        ),
                        SizedBox(width: 8),
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
                        SizedBox(width: 8),
                        Text(
                          widget.response.contentTypeLabel,
                          style: TextStyle(
                            color: TColors.cyan,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          widget.response.timeLabel,
                          style: TextStyle(
                            color: TColors.mutedText,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          widget.response.bodySizeLabel,
                          style: TextStyle(
                            color: TColors.mutedText,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                        SizedBox(width: 8),
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

  void _openCompareDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => CompareSourceDialog(currentResponse: widget.response),
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

// _TerminalLoader removed — use TerminalLoader from terminal_theme.dart
