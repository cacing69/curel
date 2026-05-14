import 'package:curel/domain/snippets/snippet_generator.dart';
import 'package:curel/domain/snippets/snippet_registry.dart';
import 'package:curel/domain/snippets/snippet_service.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:highlight/highlight.dart' show highlight, Node;

class SnippetDialog extends ConsumerStatefulWidget {
  final String curlCommand;

  const SnippetDialog({required this.curlCommand, super.key});

  @override
  ConsumerState<SnippetDialog> createState() => _SnippetDialogState();
}

class _SnippetDialogState extends ConsumerState<SnippetDialog> {
  late SnippetGenerator _selected;
  Snippet? _snippet;

  @override
  void initState() {
    super.initState();
    _selected = ref.read(snippetRegistryProvider).available.first;
    _generate();
  }

  void _generate() {
    final request = snippetRequestFromCurlString(widget.curlCommand);
    if (request != null) {
      _snippet = _selected.generate(request);
    } else {
      _snippet = null;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final generators = ref.read(snippetRegistryProvider).available;

    return AlertDialog(
      backgroundColor: TColors.background,
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: double.maxFinite,
        height: 500,
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: TColors.surface,
              child: Row(
                children: [
                  Icon(Icons.code, size: 16, color: TColors.purple),
                  SizedBox(width: 8),
                  Text(
                    'code snippet',
                    style: TextStyle(
                      color: TColors.foreground,
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Spacer(),
                  GestureDetector(
                    onTap: () {
                      if (_snippet != null) {
                        Clipboard.setData(ClipboardData(text: _snippet!.code));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('copied to clipboard'),
                            backgroundColor: TColors.green,
                          ),
                        );
                      }
                    },
                    child: Icon(Icons.copy, size: 16, color: _snippet != null ? TColors.foreground : TColors.mutedText),
                  ),
                  SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(Icons.close, size: 16, color: TColors.mutedText),
                  ),
                ],
              ),
            ),
            Container(
              height: 1,
              color: TColors.border,
            ),
            Container(
              height: 32,
              padding: EdgeInsets.symmetric(horizontal: 8),
              color: TColors.surface,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: generators.length,
                separatorBuilder: (_, _) => SizedBox(width: 4),
                itemBuilder: (context, i) {
                  final g = generators[i];
                  final selected = g.id == _selected.id;
                  return GestureDetector(
                    onTap: () {
                      _selected = g;
                      _generate();
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: selected ? TColors.green : Colors.transparent,
                            width: 1,
                          ),
                        ),
                      ),
                      child: Align(
                        alignment: Alignment.center,
                        child: Text(
                          g.name,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: selected ? TColors.foreground : TColors.mutedText,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              height: 1,
              color: TColors.border,
            ),
            Expanded(
              child: _snippet != null
                  ? _buildHighlighted(_snippet!.code, _snippet!.language)
                  : Center(
                      child: Text(
                        'failed to parse request',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: TColors.red,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHighlighted(String code, String language) {
    final result = highlight.parse(code, language: language);
    final nodes = result.nodes;

    if (nodes == null || nodes.isEmpty) {
      return _plainText(code);
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(12),
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 400,
        ),
        child: SingleChildScrollView(
          child: SelectableText.rich(
            _buildTextSpan(nodes),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: TColors.text,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _plainText(String code) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(12),
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 400,
        ),
        child: SingleChildScrollView(
          child: SelectableText(
            code,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: TColors.text,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  TextSpan _buildTextSpan(List<Node> nodes, {String? parentClass}) {
    final defaultColor = syntaxTheme['root']?.color ?? TColors.text;
    final spans = <TextSpan>[];
    var currentSpans = spans;
    final stack = <List<TextSpan>>[];

    void traverse(Node node) {
      if (node.value != null) {
        currentSpans.add(TextSpan(
          text: node.value,
          style: node.className == null
              ? TextStyle(color: defaultColor)
              : (syntaxTheme[node.className!] ?? TextStyle(color: defaultColor)),
        ));
      } else if (node.children != null) {
        final tmp = <TextSpan>[];
        currentSpans.add(TextSpan(
          children: tmp,
          style: node.className == null
              ? TextStyle(color: defaultColor)
              : (syntaxTheme[node.className!] ?? TextStyle(color: defaultColor)),
        ));
        stack.add(currentSpans);
        currentSpans = tmp;

        for (final n in node.children!) {
          traverse(n);
          if (n == node.children!.last) {
            currentSpans = stack.isEmpty ? spans : stack.removeLast();
          }
        }
      }
    }

    for (final node in nodes) {
      traverse(node);
    }

    final style = parentClass != null
        ? (syntaxTheme[parentClass] ?? TextStyle(color: defaultColor))
        : TextStyle(color: defaultColor);

    return TextSpan(children: spans, style: style);
  }
}
