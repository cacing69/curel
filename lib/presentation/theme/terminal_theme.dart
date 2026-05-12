import 'package:curel/presentation/theme/app_tokens.dart';
import 'package:flutter/material.dart';

// ── Terminal-style loading spinner ────────────────────────────────

class TerminalLoader extends StatefulWidget {
  /// [compact] shows only the spinning braille character — no "loading" label.
  /// Use compact for inline/icon-replacement contexts (e.g. toolbar buttons).
  final bool compact;

  const TerminalLoader({this.compact = false, super.key});

  @override
  State<TerminalLoader> createState() => _TerminalLoaderState();
}

class _TerminalLoaderState extends State<TerminalLoader>
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
        final spinChar = Text(
          _frames[index],
          style: TextStyle(
            color: TColors.green,
            fontFamily: 'monospace',
            fontSize: widget.compact ? 13 : 16,
          ),
        );

        if (widget.compact) return spinChar;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            spinChar,
            const SizedBox(width: 8),
            Text(
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

abstract class TColors {
  static Color get background => $tokens.background;
  static Color get surface => $tokens.surface;
  static Color get foreground => $tokens.foreground;
  static Color get comment => $tokens.mutedText;
  static Color get cyan => $tokens.cyan;
  static Color get green => $tokens.green;
  static Color get orange => $tokens.orange;
  static Color get pink => $tokens.pink;
  static Color get purple => $tokens.purple;
  static Color get red => $tokens.red;
  static Color get yellow => $tokens.yellow;

  // Semantic aliases
  static Color get text => $tokens.text;
  static Color get mutedText => $tokens.mutedText;
  static Color get accent => $tokens.accent;
  static Color get accentText => $tokens.accent;
  static Color get error => $tokens.error;
  static Color get warning => $tokens.warning;
  static Color get border => $tokens.border;
}

const syntaxTheme = {
  'root': TextStyle(
    color: Color(0xffabb2bf),
    backgroundColor: Color(0xff282c34),
  ),
  'comment': TextStyle(color: Color(0xff5c6370), fontStyle: FontStyle.italic),
  'quote': TextStyle(color: Color(0xff5c6370), fontStyle: FontStyle.italic),
  'doctag': TextStyle(color: Color(0xffc678dd)),
  'keyword': TextStyle(color: Color(0xffc678dd)),
  'formula': TextStyle(color: Color(0xffc678dd)),
  'section': TextStyle(color: Color(0xffe06c75)),
  'name': TextStyle(color: Color(0xffe06c75)),
  'selector-tag': TextStyle(color: Color(0xffe06c75)),
  'deletion': TextStyle(color: Color(0xffe06c75)),
  'subst': TextStyle(color: Color(0xffe06c75)),
  'literal': TextStyle(color: Color(0xff56b6c2)),
  'string': TextStyle(color: Color(0xff98c379)),
  'regexp': TextStyle(color: Color(0xff98c379)),
  'addition': TextStyle(color: Color(0xff98c379)),
  'attribute': TextStyle(color: Color(0xff98c379)),
  'meta-string': TextStyle(color: Color(0xff98c379)),
  'built_in': TextStyle(color: Color(0xffe6c07b)),
  'attr': TextStyle(color: Color(0xffd19a66)),
  'variable': TextStyle(color: Color(0xffd19a66)),
  'template-variable': TextStyle(color: Color(0xffd19a66)),
  'type': TextStyle(color: Color(0xffd19a66)),
  'selector-class': TextStyle(color: Color(0xffd19a66)),
  'selector-attr': TextStyle(color: Color(0xffd19a66)),
  'selector-pseudo': TextStyle(color: Color(0xffd19a66)),
  'number': TextStyle(color: Color(0xffd19a66)),
  'symbol': TextStyle(color: Color(0xff61aeee)),
  'bullet': TextStyle(color: Color(0xff61aeee)),
  'link': TextStyle(color: Color(0xff61aeee)),
  'meta': TextStyle(color: Color(0xff61aeee)),
  'selector-id': TextStyle(color: Color(0xff61aeee)),
  'title': TextStyle(color: Color(0xff61aeee)),
  'emphasis': TextStyle(fontStyle: FontStyle.italic),
  'strong': TextStyle(fontWeight: FontWeight.bold),
};

void showTerminalToast(
  BuildContext context,
  String message, {
  double topOffset = 16,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => Positioned.fill(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: topOffset, left: 12, right: 12),
            child: _ToastOverlay(
              message: message,
              onDismiss: () => entry.remove(),
              actionLabel: actionLabel,
              onAction: onAction,
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
}

class _ToastOverlay extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _ToastOverlay({
    required this.message,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  @override
  State<_ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<_ToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    )..forward();

    // Auto-dismiss after 2s, but longer if there's an action
    final duration = widget.actionLabel != null ? 5 : 2;
    Future.delayed(Duration(seconds: duration), _dismiss);
  }

  void _dismiss() {
    if (!mounted) return;
    _controller.reverse().then((_) => widget.onDismiss());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.2),
          end: Offset.zero,
        ).animate(_controller),
        child: Material(
          color: TColors.surface,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: TColors.border),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.terminal_outlined,
                  size: 14,
                  color: TColors.green,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.message.toLowerCase(),
                    style: TextStyle(
                      color: TColors.foreground,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
                if (widget.actionLabel != null) ...[
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () {
                      widget.onAction?.call();
                      _dismiss();
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chevron_right,
                          size: 14,
                          color: TColors.green,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.actionLabel!.toLowerCase(),
                          style: TextStyle(
                            color: TColors.green,
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
