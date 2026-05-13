import 'package:curel/data/models/curl_response.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum ResponseTab { headers, body, verbose, trace }

class ResponseToolbar extends StatelessWidget {
  final CurlResponse response;
  final ResponseTab selectedTab;
  final bool showHtmlPreview;
  final bool searchActive;
  final bool prettify;
  final bool showLineNumbers;
  final bool showBackButton;
  final VoidCallback? onBack;
  final void Function(ResponseTab tab, {bool showHtmlPreview, bool? searchActive}) onTabChanged;
  final VoidCallback? onCopy;
  final VoidCallback? onSaveResponse;
  final VoidCallback? onSaveSample;
  final VoidCallback? onViewSnippet;
  final VoidCallback? onCompare;
  final VoidCallback? onOpenFullscreen;
  final VoidCallback onToggleSearch;
  final VoidCallback onTogglePrettify;
  final VoidCallback onToggleLineNumbers;

  const ResponseToolbar({
    required this.response,
    required this.selectedTab,
    required this.showHtmlPreview,
    required this.searchActive,
    required this.prettify,
    required this.showLineNumbers,
    this.showBackButton = false,
    this.onBack,
    required this.onTabChanged,
    this.onCopy,
    this.onSaveResponse,
    this.onSaveSample,
    this.onViewSnippet,
    this.onCompare,
    this.onOpenFullscreen,
    required this.onToggleSearch,
    required this.onTogglePrettify,
    required this.onToggleLineNumbers,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: TColors.surface,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Back + Tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (showBackButton) ...[
                  GestureDetector(
                    onTap: onBack ?? () => Navigator.of(context).pop(),
                    child: Icon(Icons.arrow_back, size: 18, color: TColors.mutedText),
                  ),
                  SizedBox(width: 8),
                ],
                _buildTab('headers', ResponseTab.headers, false),
                SizedBox(width: 8),
                _buildTab('body', ResponseTab.body, false),
                if (response.isHtml) ...[
                  SizedBox(width: 8),
                  _buildTab('preview', ResponseTab.body, true),
                ],
                if (response.verboseLog != null && response.verboseLog!.isNotEmpty) ...[
                  SizedBox(width: 8),
                  _buildTab('verbose', ResponseTab.verbose, false),
                ],
                if (response.traceLog != null && response.traceLog!.isNotEmpty) ...[
                  SizedBox(width: 8),
                  _buildTab('trace', ResponseTab.trace, false),
                ],
              ],
            ),
          ),
          SizedBox(height: 6),
          // Row 2: Info
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text(
                  '${response.statusCode ?? '-'} ${response.statusMessage}',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: (response.statusCode ?? 0) >= 200 && (response.statusCode ?? 0) < 300
                        ? TColors.green
                        : TColors.red,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  response.timeLabel,
                  style: TextStyle(color: TColors.mutedText, fontSize: 11, fontFamily: 'monospace'),
                ),
                SizedBox(width: 8),
                Text(
                  response.bodySizeLabel,
                  style: TextStyle(color: TColors.mutedText, fontSize: 11, fontFamily: 'monospace'),
                ),
                SizedBox(width: 8),
                Text(
                  response.contentTypeLabel,
                  style: TextStyle(color: TColors.cyan, fontSize: 11, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          SizedBox(height: 6),
          // Row 3: Actions
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _action(Icons.copy, onCopy ?? () {
                  Clipboard.setData(ClipboardData(text: response.bodyText));
                  showTerminalToast(context, 'copied to clipboard');
                }),
                SizedBox(width: 8),
                if (onSaveResponse != null) ...[
                  _action(Icons.save, onSaveResponse!),
                  SizedBox(width: 8),
                ],
                if (onViewSnippet != null) ...[
                  _action(Icons.code, onViewSnippet!),
                  SizedBox(width: 8),
                ],
                if (onSaveSample != null) ...[
                  _action(Icons.archive, onSaveSample!),
                  SizedBox(width: 8),
                ],
                _action(searchActive ? Icons.search_off : Icons.search, onToggleSearch,
                    active: searchActive),
                if (response.highlightLanguage == 'json') ...[
                  SizedBox(width: 8),
                  _action(prettify ? Icons.auto_fix_high : Icons.auto_fix_off, onTogglePrettify,
                      active: prettify),
                ],
                SizedBox(width: 8),
                if (onCompare != null) ...[
                  _action(Icons.compare_arrows, onCompare!),
                  SizedBox(width: 8),
                ],
                _action(Icons.format_list_numbered, onToggleLineNumbers,
                    active: showLineNumbers),
                if (onOpenFullscreen != null) ...[
                  SizedBox(width: 8),
                  _action(Icons.fullscreen, onOpenFullscreen!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String label, ResponseTab tab, bool isHtmlPreview) {
    final selected = isHtmlPreview
        ? showHtmlPreview
        : selectedTab == tab && !showHtmlPreview;
    return FlatTab(
      label: label,
      selected: selected,
      onTap: () => onTabChanged(tab,
          showHtmlPreview: isHtmlPreview, searchActive: isHtmlPreview ? false : null),
    );
  }

  Widget _action(IconData icon, VoidCallback onTap, {bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, size: 16, color: active ? TColors.green : TColors.mutedText),
    );
  }
}


