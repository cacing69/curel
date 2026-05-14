import 'package:curel/data/models/curl_response.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/chunked_text_viewer.dart';
import 'package:curel/presentation/widgets/html_preview.dart';
import 'package:curel/presentation/widgets/searchable_text.dart';
import 'package:curel/presentation/widgets/diff_view.dart';
import 'package:curel/presentation/widgets/response_toolbar.dart';
import 'package:curel/domain/services/request_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ResponseViewer extends StatelessWidget {
  final CurlResponse? response;
  final String? error;
  final String? log;
  final bool isLoading;
  final ResponseTab selectedTab;
  final bool showHtmlPreview;
  final bool searchActive;
  final bool prettify;
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
        final lines = response!.headersLines;
        return ListView.builder(
          padding: EdgeInsets.all(8),
          itemCount: lines.length,
          itemBuilder: (context, index) {
            return SelectionArea(
              child: Text.rich(
                TextSpan(children: lines[index]),
                style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: TColors.text),
              ),
            );
          },
        );
      }

      if (selectedTab == ResponseTab.verbose) {
        final lines = response!.verboseLogLines;
        return ListView.builder(
          padding: EdgeInsets.all(8),
          itemCount: lines.length,
          itemBuilder: (context, index) {
            return SelectionArea(
              child: Text.rich(
                TextSpan(children: lines[index]),
              ),
            );
          },
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

      return _buildHighlightedBody(response!, prettify);
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
  ) {
    return ChunkedTextViewer(
      text: response.getBodyText(prettify),
      language: response.highlightLanguage,
    );
  }
}

class FullscreenResponseViewer extends StatefulWidget {
  final CurlResponse response;
  final String? baseCurlText;
  final String? projectId;
  final RequestService? requestService;
  final VoidCallback? onSaveResponse;
  final VoidCallback? onSaveSample;
  final VoidCallback? onViewSnippet;
  final VoidCallback? onCompare;
  final VoidCallback? onCopyActivePreview;

  const FullscreenResponseViewer({
    required this.response,
    this.baseCurlText,
    this.projectId,
    this.requestService,
    this.onSaveResponse,
    this.onSaveSample,
    this.onViewSnippet,
    this.onCompare,
    this.onCopyActivePreview,
    super.key,
  });

  @override
  State<FullscreenResponseViewer> createState() =>
      _FullscreenResponseViewerState();
}

class _FullscreenResponseViewerState extends State<FullscreenResponseViewer> {
  var _selectedTab = ResponseTab.body;
  bool _showHtmlPreview = false;
  bool _searchActive = false;
  bool _prettify = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ResponseToolbar(
              response: widget.response,
              selectedTab: _selectedTab,
              showHtmlPreview: _showHtmlPreview,
              searchActive: _searchActive,
              prettify: _prettify,
              showBackButton: true,
              onBack: () => Navigator.of(context).pop(),
              onTabChanged: (tab, {showHtmlPreview = false, searchActive}) {
                setState(() {
                  _selectedTab = tab;
                  _showHtmlPreview = showHtmlPreview;
                  if (searchActive != null) _searchActive = searchActive;
                });
              },
              onCopy: widget.onCopyActivePreview ?? (() {
                Clipboard.setData(
                  ClipboardData(text: widget.response.bodyText),
                );
                showTerminalToast(context, 'copied to clipboard');
              }),
              onSaveResponse: widget.onSaveResponse,
              onViewSnippet: widget.onViewSnippet,
              onSaveSample: widget.onSaveSample,
              onCompare: widget.onCompare ?? (() => _openCompareDialog(context)),
              onToggleSearch: () => setState(() {
                _searchActive = !_searchActive;
                if (_searchActive) _showHtmlPreview = false;
              }),
              onTogglePrettify: () => setState(() => _prettify = !_prettify),
            ),
            Container(height: 1, color: TColors.border),
            Expanded(
              child: ResponseViewer(
                response: widget.response,
                selectedTab: _selectedTab,
                showHtmlPreview: _showHtmlPreview,
                searchActive: _searchActive,
                prettify: _prettify,
                onCloseSearch: () => setState(() => _searchActive = false),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCompareDialog(BuildContext context) {
    if (widget.projectId == null || widget.baseCurlText == null || widget.requestService == null) return;
    showDialog(
      context: context,
      builder: (_) => CompareSourceDialog(
        baseCurlText: widget.baseCurlText!,
        projectId: widget.projectId!,
        requestService: widget.requestService!,
        currentResponse: widget.response,
      ),
    );
  }
}

void openFullscreenResponse(
  BuildContext context,
  CurlResponse response, {
  String? baseCurlText,
  String? projectId,
  RequestService? requestService,
  VoidCallback? onSaveResponse,
  VoidCallback? onSaveSample,
  VoidCallback? onViewSnippet,
  VoidCallback? onCompare,
  VoidCallback? onCopyActivePreview,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => FullscreenResponseViewer(
        response: response,
        baseCurlText: baseCurlText,
        projectId: projectId,
        requestService: requestService,
        onSaveResponse: onSaveResponse,
        onSaveSample: onSaveSample,
        onViewSnippet: onViewSnippet,
        onCompare: onCompare,
        onCopyActivePreview: onCopyActivePreview,
      ),
    ),
  );
}

// _TerminalLoader removed — use TerminalLoader from terminal_theme.dart
