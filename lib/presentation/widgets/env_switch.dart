import 'package:curel/domain/providers/services.dart';
import 'package:curel/presentation/screens/env_page.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EnvSwitch extends ConsumerStatefulWidget {
  final String? projectId;
  final VoidCallback? onChanged;

  const EnvSwitch({this.projectId, this.onChanged, super.key});

  @override
  ConsumerState<EnvSwitch> createState() => _EnvSwitchState();
}

class _EnvSwitchState extends ConsumerState<EnvSwitch> {
  String? _activeName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final active = await ref.read(envServiceProvider).getActive(widget.projectId);
    if (mounted) setState(() => _activeName = active?.name);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (details) async {
        final envs = await ref.read(envServiceProvider).getAll(widget.projectId);
        if (!mounted) return;
        final active = await ref.read(envServiceProvider).getActive(widget.projectId);
        if (!mounted) return;
        final renderBox = this.context.findRenderObject() as RenderBox;
        final offset = renderBox.localToGlobal(Offset.zero);
        showMenu<String>(
          context: this.context,
          elevation: 0,
          constraints: const BoxConstraints(maxWidth: 180),
          position: RelativeRect.fromLTRB(
            offset.dx,
            offset.dy + renderBox.size.height,
            offset.dx + renderBox.size.width,
            0,
          ),
          color: TColors.surface,
          items: [
            ...envs.map(
              (e) => PopupMenuItem<String>(
                value: e.id,
                height: 36,
                child: Row(
                  children: [
                    Icon(
                      e.id == active?.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 14,
                      color: e.id == active?.id
                          ? TColors.green
                          : TColors.mutedText,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: e.id == active?.id
                              ? TColors.green
                              : TColors.foreground,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            PopupMenuItem<String>(
              value: 'manage',
              height: 36,
              child: Row(
                children: [
                  Icon(Icons.widgets, size: 14, color: TColors.mutedText),
                  const SizedBox(width: 8),
                  Text(
                    'env',
                    style: TextStyle(
                      color: TColors.foreground,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ).then((value) async {
          if (value == null) return;
          if (!mounted) return;
          if (value == 'manage') {
            Navigator.of(this.context)
                .push(
                  MaterialPageRoute(
                    builder: (_) => EnvPage(
                      projectId: widget.projectId,
                    ),
                  ),
                )
                .then((_) {
                  _load();
                  widget.onChanged?.call();
                });
          } else {
            await ref.read(envServiceProvider).setActive(widget.projectId, value);
            _load();
            widget.onChanged?.call();
          }
        });
      },
      child: Container(
        height: 28,
        padding: EdgeInsets.symmetric(horizontal: 8),
        color: TColors.surface,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.data_object, size: 14, color: TColors.cyan),
            if (_activeName != null) ...[
              const SizedBox(width: 4),
              Text(
                _activeName!.length > 6
                    ? '${_activeName!.substring(0, 4)}…'
                    : _activeName!,
                style: TextStyle(
                  color: TColors.cyan,
                  fontFamily: 'monospace',
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
