import 'package:curel/domain/providers/app_state.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/response_toolbar.dart';
import 'package:curel/presentation/widgets/response_viewer.dart';
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
            ResponseToolbar(
              response: rs.response!,
              selectedTab: rs.selectedTab,
              showHtmlPreview: rs.showHtmlPreview,
              searchActive: rs.searchActive,
              prettify: rs.prettify,
              showLineNumbers: rs.showLineNumbers,
              onTabChanged: (tab, {showHtmlPreview = false, searchActive}) {
                ref.read(responseStateProvider.notifier).update((s) => s.copyWith(
                      selectedTab: tab,
                      showHtmlPreview: showHtmlPreview,
                      searchActive: searchActive ?? s.searchActive,
                    ));
              },
              onCopy: onCopyActivePreview,
              onSaveResponse: onSaveResponse,
              onViewSnippet: onViewSnippet,
              onSaveSample: onSaveSample,
              onCompare: onCompare,
              onOpenFullscreen: onOpenFullscreen,
              onToggleSearch: () => ref
                  .read(responseStateProvider.notifier)
                  .update((s) => s.copyWith(searchActive: !s.searchActive)),
              onTogglePrettify: () => ref
                  .read(responseStateProvider.notifier)
                  .update((s) => s.copyWith(prettify: !s.prettify)),
              onToggleLineNumbers: () => ref
                  .read(responseStateProvider.notifier)
                  .update((s) => s.copyWith(showLineNumbers: !s.showLineNumbers)),
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
