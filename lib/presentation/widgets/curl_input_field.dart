import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/curl_highlight_controller.dart';
import 'package:flutter/material.dart';

class CurlInputField extends StatelessWidget {
  final CurlHighlightController controller;
  final FocusNode focusNode;
  final GlobalKey textFieldKey;
  final VoidCallback onClear;
  final int? maxLines;
  final int minLines;

  const CurlInputField({
    required this.controller,
    required this.focusNode,
    required this.textFieldKey,
    required this.onClear,
    this.maxLines = 8,
    this.minLines = 3,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final unlimited = maxLines == null;
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '❯ ',
          style: TextStyle(
            color: TColors.green,
            fontFamily: 'monospace',
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        Expanded(
          child: TextField(
            key: textFieldKey,
            focusNode: focusNode,
            controller: controller,
            maxLines: unlimited ? null : maxLines,
            minLines: unlimited ? null : minLines,
            expands: unlimited,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            cursorColor: TColors.green,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.4,
              color: TColors.text,
            ),
            decoration: const InputDecoration(
              hintText: 'paste or type a curl command...',
              hintStyle: TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.4,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    );
    return Stack(
      children: [
        if (unlimited) SizedBox.expand(child: content) else content,
        Positioned(
          top: 0,
          right: 0,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              if (controller.text.isEmpty) {
                return const SizedBox.shrink();
              }
              return GestureDetector(
                onTap: onClear,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: TColors.surface,
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Icon(Icons.close, size: 12, color: TColors.red),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
