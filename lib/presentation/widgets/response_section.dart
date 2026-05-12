import 'package:curel/domain/providers/app_state.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/response_viewer.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ResponseSection extends ConsumerWidget {
  final bool isHorizontal;
  final VoidCallback onCopyActivePreview;
  final VoidCallback onSaveResponse;
  final VoidCallback onOpenFullscreen;
  final VoidCallback? onViewSnippet;
  final VoidCallback? onSaveSample;
  final VoidCallback? onCompare;

  const ResponseSection({
    required this.isHorizontal,
    required this.onCopyActivePreview,
    required this.onSaveResponse,
    required this.onOpenFullscreen,
    this.onViewSnippet,
    this.onSaveSample,
    this.onCompare,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rs = ref.watch(responseStateProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rs.response != null || rs.error != null) ...[
          Container(
            height: isHorizontal ? null : 1,
            width: isHorizontal ? 1 : null,
            color: TColors.border,
          ),
          if (rs.response != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Tabs
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FlatTab(
                          label: 'headers',
                          selected: rs.selectedTab == ResponseTab.headers,
                          onTap: () => ref
                              .read(responseStateProvider.notifier)
                              .update((s) => s.copyWith(
                                    selectedTab: ResponseTab.headers,
                                    showHtmlPreview: false,
                                  )),
                        ),
                        SizedBox(width: 8),
                        FlatTab(
                          label: 'body',
                          selected: rs.selectedTab == ResponseTab.body && !rs.showHtmlPreview,
                          onTap: () => ref
                              .read(responseStateProvider.notifier)
                              .update((s) => s.copyWith(
                                    selectedTab: ResponseTab.body,
                                    showHtmlPreview: false,
                                  )),
                        ),
                        if (rs.response!.isHtml) ...[
                          SizedBox(width: 8),
                          FlatTab(
                            label: 'preview',
                            selected: rs.showHtmlPreview,
                            onTap: () => ref
                                .read(responseStateProvider.notifier)
                                .update((s) => s.copyWith(
                                      selectedTab: ResponseTab.body,
                                      showHtmlPreview: true,
                                      searchActive: false,
                                    )),
                          ),
                        ],
                        if (rs.response!.verboseLog != null &&
                            rs.response!.verboseLog!.isNotEmpty) ...[
                          SizedBox(width: 8),
                          FlatTab(
                            label: 'verbose',
                            selected: rs.selectedTab == ResponseTab.verbose,
                            onTap: () => ref
                                .read(responseStateProvider.notifier)
                                .update((s) => s.copyWith(
                                      selectedTab: ResponseTab.verbose,
                                      showHtmlPreview: false,
                                    )),
                          ),
                        ],
                        if (rs.response!.traceLog != null &&
                            rs.response!.traceLog!.isNotEmpty) ...[
                          SizedBox(width: 8),
                          FlatTab(
                            label: 'trace',
                            selected: rs.selectedTab == ResponseTab.trace,
                            onTap: () => ref
                                .read(responseStateProvider.notifier)
                                .update((s) => s.copyWith(
                                      selectedTab: ResponseTab.trace,
                                      showHtmlPreview: false,
                                    )),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: 4),
                  // Row 2: Info
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Text(
                          '${rs.response!.statusCode ?? '-'}',
                          style: TextStyle(
                            color: (rs.response!.statusCode ?? 0) >= 200 &&
                                    (rs.response!.statusCode ?? 0) < 300
                                ? TColors.green
                                : TColors.red,
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          rs.response!.timeLabel,
                          style: TextStyle(
                            color: TColors.mutedText,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          rs.response!.bodySizeLabel,
                          style: TextStyle(
                            color: TColors.mutedText,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          rs.response!.contentTypeLabel,
                          style: TextStyle(
                            color: TColors.cyan,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 4),
                  // Row 3: Actions
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: onCopyActivePreview,
                          child: Icon(Icons.copy, size: 16, color: TColors.mutedText),
                        ),
                        SizedBox(width: 8),
                        GestureDetector(
                          onTap: onSaveResponse,
                          child: Icon(Icons.save, size: 16, color: TColors.mutedText),
                        ),
                        if (onViewSnippet != null) ...[
                          SizedBox(width: 8),
                          GestureDetector(
                            onTap: onViewSnippet,
                            child: Icon(Icons.code, size: 16, color: TColors.mutedText),
                          ),
                        ],
                        if (onSaveSample != null) ...[
                          SizedBox(width: 8),
                          GestureDetector(
                            onTap: onSaveSample,
                            child: Icon(Icons.archive, size: 16, color: TColors.mutedText),
                          ),
                        ],
                        SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => ref
                              .read(responseStateProvider.notifier)
                              .update((s) => s.copyWith(searchActive: !s.searchActive)),
                          child: Icon(
                            rs.searchActive ? Icons.search_off : Icons.search,
                            size: 16,
                            color: rs.searchActive ? TColors.green : TColors.mutedText,
                          ),
                        ),
                        if (rs.response?.highlightLanguage == 'json') ...[
                          SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => ref
                                .read(responseStateProvider.notifier)
                                .update((s) => s.copyWith(prettify: !s.prettify)),
                            child: Icon(
                              rs.prettify ? Icons.auto_fix_high : Icons.auto_fix_off,
                              size: 16,
                              color: rs.prettify ? TColors.green : TColors.mutedText,
                            ),
                          ),
                        ],
                        SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => ref
                              .read(responseStateProvider.notifier)
                              .update((s) => s.copyWith(showLineNumbers: !s.showLineNumbers)),
                          child: Icon(
                            Icons.format_list_numbered,
                            size: 16,
                            color: rs.showLineNumbers ? TColors.green : TColors.mutedText,
                          ),
                        ),
                        if (onCompare != null) ...[
                          SizedBox(width: 8),
                          GestureDetector(
                            onTap: onCompare,
                            child: Icon(Icons.compare_arrows, size: 16, color: TColors.mutedText),
                          ),
                        ],
                        SizedBox(width: 8),
                        GestureDetector(
                          onTap: onOpenFullscreen,
                          child: Icon(Icons.fullscreen, size: 16, color: TColors.mutedText),
                        ),
                      ],
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
            isLoading: rs.isLoading,
            response: rs.response,
            error: rs.error,
            log: rs.log,
            selectedTab: rs.selectedTab,
            showHtmlPreview: rs.showHtmlPreview,
            searchActive: rs.searchActive,
            prettify: rs.prettify,
            showLineNumbers: rs.showLineNumbers,
            onCloseSearch: () => ref
                .read(responseStateProvider.notifier)
                .update((s) => s.copyWith(searchActive: false)),
          ),
        ),
      ],
    );
  }
}
