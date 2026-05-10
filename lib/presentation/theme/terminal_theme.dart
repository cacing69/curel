import 'package:flutter/material.dart';

abstract class TColors {
  // Dracula theme palette
  static const background = Color(0xFF282A36);
  static const surface = Color(0xFF44475A);
  static const foreground = Color(0xFFF8F8F2);
  static const comment = Color(0xFF6272A4);
  static const cyan = Color(0xFF8BE9FD);
  static const green = Color(0xFF50FA7B);
  static const orange = Color(0xFFFFB86C);
  static const pink = Color(0xFFFF79C6);
  static const purple = Color(0xFFBD93F9);
  static const red = Color(0xFFFF5555);
  static const yellow = Color(0xFFF1FA8C);

  // Semantic aliases
  static const text = foreground;
  static const mutedText = comment;
  static const accent = green;
  static const accentText = green;
  static const error = red;
  static const warning = yellow;
  static const border = comment;
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: TColors.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.terminal_outlined,
                  size: 14,
                  color: TColors.green,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.message.toLowerCase(),
                    style: const TextStyle(
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
                        const Icon(
                          Icons.chevron_right,
                          size: 14,
                          color: TColors.green,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.actionLabel!.toLowerCase(),
                          style: const TextStyle(
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
