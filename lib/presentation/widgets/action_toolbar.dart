import 'package:curel/domain/providers/app_state.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/editor_dashboard.dart';
import 'package:curel/presentation/widgets/more_menu.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ActionToolbar extends ConsumerWidget {
  final String curlText;
  final VoidCallback onBuilder;
  final VoidCallback onPaste;
  final VoidCallback onResolvedPreview;
  final VoidCallback onExecute;
  final void Function(String curl) onHistorySelect;
  final VoidCallback onHelp;
  final void Function(BuildContext) onNavigateAbout;
  final void Function(BuildContext) onNavigateFeedback;
  final void Function(BuildContext) onNavigateSettings;
  final void Function(BuildContext) onNavigateHistory;

  const ActionToolbar({
    required this.curlText,
    required this.onBuilder,
    required this.onPaste,
    required this.onResolvedPreview,
    required this.onExecute,
    required this.onHistorySelect,
    required this.onHelp,
    required this.onNavigateAbout,
    required this.onNavigateFeedback,
    required this.onNavigateSettings,
    required this.onNavigateHistory,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rs = ref.watch(responseStateProvider);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          CompactIconButton(icon: Icons.science, onTap: onBuilder),
          CompactIconButton(
            icon: Icons.copy,
            onTap: () {
              if (curlText.isNotEmpty) {
                Clipboard.setData(ClipboardData(text: curlText));
                showTerminalToast(context, 'copied');
              }
            },
          ),
          CompactIconButton(icon: Icons.content_paste, onTap: onPaste),
          CompactIconButton(icon: Icons.code, onTap: onResolvedPreview),

          const Spacer(),

          MoreMenu(
            onAbout: () => onNavigateAbout(context),
            onFeedback: () => onNavigateFeedback(context),
            onHelp: () => onHelp(),
            onSettings: () => onNavigateSettings(context),
            onHistory: () => onNavigateHistory(context),
          ),

          const SizedBox(width: 8),
          TermButton(
            icon: Icons.play_arrow,
            label: 'exec',
            onTap: rs.isLoading ? null : onExecute,
            accent: true,
          ),
        ],
      ),
    );
  }
}
