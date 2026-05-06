import 'dart:math' as math;

import 'package:Curel/presentation/theme/terminal_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight2/themes/atom-one-dark.dart';
import 'package:highlight/highlight.dart' show highlight, Node;

class SearchableText extends StatefulWidget {
  final String text;
  final bool searchActive;
  final TextStyle style;
  final EdgeInsetsGeometry padding;
  final String? syntaxLanguage;
  final Map<String, TextStyle>? syntaxTheme;
  final VoidCallback? onClose;

  const SearchableText({
    required this.text,
    this.searchActive = false,
    this.style = const TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      color: TColors.text,
    ),
    this.padding = const EdgeInsets.all(4),
    this.syntaxLanguage,
    this.syntaxTheme,
    this.onClose,
    super.key,
  });

  @override
  State<SearchableText> createState() => _SearchableTextState();
}

class _SearchableTextState extends State<SearchableText> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final _contentKey = GlobalKey();

  String _query = '';
  List<TextRange> _matches = [];
  int _activeIndex = 0;

  @override
  void didUpdateWidget(covariant SearchableText oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.text != oldWidget.text) {
      _matches = _findAllMatches(widget.text, _query);
      if (_matches.isNotEmpty && _activeIndex >= _matches.length) {
        _activeIndex = 0;
      }
    }

    if (!widget.searchActive && oldWidget.searchActive) {
      _resetSearch();
    }

    if (widget.searchActive && !oldWidget.searchActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _resetSearch() {
    _searchController.clear();
    _query = '';
    _matches = [];
    _activeIndex = 0;
    _focusNode.unfocus();
  }

  void _onQueryChanged(String query) {
    final matches = _findAllMatches(widget.text, query);
    setState(() {
      _query = query;
      _matches = matches;
      _activeIndex = 0;
    });
    if (matches.isNotEmpty) {
      _scrollToMatch(0);
    }
  }

  void _nextMatch() {
    if (_matches.isEmpty) return;
    final next = (_activeIndex + 1) % _matches.length;
    setState(() => _activeIndex = next);
    _scrollToMatch(next);
  }

  void _prevMatch() {
    if (_matches.isEmpty) return;
    final prev = (_activeIndex - 1 + _matches.length) % _matches.length;
    setState(() => _activeIndex = prev);
    _scrollToMatch(prev);
  }

  List<TextRange> _findAllMatches(String text, String query) {
    if (query.isEmpty) return [];
    final results = <TextRange>[];
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    var start = 0;
    while (start < lowerText.length) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) break;
      results.add(TextRange(start: index, end: index + query.length));
      start = index + 1;
    }
    return results;
  }

  void _scrollToMatch(int index) {
    if (index >= _matches.length || _matches.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      final match = _matches[index];
      final span = _buildSpan();
      final painter = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
        strutStyle: StrutStyle.fromTextStyle(widget.style),
      );

      final renderBox =
          _contentKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) return;

      final resolvedPadding = widget.padding.resolve(TextDirection.ltr);
      painter.layout(
        maxWidth: math.max(0, renderBox.size.width - resolvedPadding.horizontal),
      );

      final offset = painter.getOffsetForCaret(
        TextPosition(offset: match.start),
        Rect.zero,
      );

      final target = math.max(0.0, offset.dy - 40);
      final maxScroll = _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        target.clamp(0.0, maxScroll),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    });
  }

  List<TextSpan> _convertSyntaxNodes(List<Node> nodes) {
    final theme = widget.syntaxTheme ?? atomOneDarkTheme;
    final defaultColor = theme['root']?.color ?? TColors.text;
    final spans = <TextSpan>[];
    var currentSpans = spans;
    final stack = <List<TextSpan>>[];

    void traverse(Node node) {
      if (node.value != null) {
        currentSpans.add(TextSpan(
          text: node.value,
          style: node.className == null
              ? TextStyle(color: defaultColor)
              : (theme[node.className!] ?? TextStyle(color: defaultColor)),
        ));
      } else if (node.children != null) {
        final tmp = <TextSpan>[];
        currentSpans.add(TextSpan(
          children: tmp,
          style: theme[node.className!] ?? TextStyle(color: defaultColor),
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

    return spans;
  }

  List<TextSpan> _syntaxHighlightedSpans() {
    if (widget.syntaxLanguage == null) return [];
    final result = highlight.parse(widget.text, language: widget.syntaxLanguage);
    if (result.nodes == null) return [];
    return _convertSyntaxNodes(result.nodes!);
  }

  List<TextSpan> _flattenSpans(List<TextSpan> spans) {
    final result = <TextSpan>[];
    void visit(TextSpan span) {
      if (span.text != null && span.text!.isNotEmpty) {
        result.add(TextSpan(text: span.text, style: span.style));
      }
      if (span.children != null) {
        for (final child in span.children!) {
          if (child is TextSpan) visit(child);
        }
      }
    }
    for (final span in spans) {
      visit(span);
    }
    return result;
  }

  TextSpan _applySearchHighlight(List<TextSpan> baseSpans) {
    final defaultColor =
        (widget.syntaxTheme ?? atomOneDarkTheme)['root']?.color ??
        TColors.text;
    final flatSpans = _flattenSpans(baseSpans);

    if (_query.isEmpty || _matches.isEmpty) {
      return TextSpan(
        style: TextStyle(color: defaultColor, fontFamily: 'monospace', fontSize: 12),
        children: flatSpans.isNotEmpty ? flatSpans : [TextSpan(text: widget.text, style: TextStyle(color: defaultColor))],
      );
    }

    final text = widget.text;
    final children = <InlineSpan>[];
    var lastEnd = 0;

    for (var i = 0; i < _matches.length; i++) {
      final match = _matches[i];

      if (match.start > lastEnd) {
        children.addAll(_sliceSpans(flatSpans, lastEnd, match.start));
      }

      final isActive = i == _activeIndex;
      final matchSpans = _sliceSpans(flatSpans, match.start, match.end);
      final highlightedSpans = matchSpans.map((span) {
        final spanColor = span.style?.color ?? defaultColor;
        return TextSpan(
          text: span.text,
          style: TextStyle(
            color: isActive ? TColors.background : spanColor,
            backgroundColor: isActive
                ? TColors.yellow
                : TColors.yellow.withValues(alpha: 0.3),
          ),
        );
      }).toList();
      children.addAll(highlightedSpans);

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      children.addAll(_sliceSpans(flatSpans, lastEnd, text.length));
    }

    return TextSpan(
      style: TextStyle(color: defaultColor, fontFamily: 'monospace', fontSize: 12),
      children: children,
    );
  }

  List<TextSpan> _sliceSpans(List<TextSpan> spans, int from, int to) {
    final result = <TextSpan>[];
    var pos = 0;

    for (final span in spans) {
      final text = span.text ?? '';
      if (text.isEmpty) continue;
      final spanStart = pos;
      final spanEnd = pos + text.length;

      if (spanEnd <= from || spanStart >= to) {
        pos = spanEnd;
        continue;
      }

      final overlapStart = math.max(spanStart, from) - pos;
      final overlapEnd = math.min(spanEnd, to) - pos;
      final slicedText = text.substring(overlapStart, overlapEnd);

      if (slicedText.isNotEmpty) {
        result.add(TextSpan(text: slicedText, style: span.style, children: span.children));
      }

      pos = spanEnd;
    }

    return result;
  }

  TextSpan _buildSpan() {
    final isSearching = widget.searchActive && _query.isNotEmpty;
    final hasSyntax = widget.syntaxLanguage != null;

    if (isSearching && hasSyntax) {
      final syntaxSpans = _syntaxHighlightedSpans();
      if (syntaxSpans.isEmpty) return _buildPlainHighlightSpan();
      return _applySearchHighlight(syntaxSpans);
    }

    if (isSearching) {
      return _buildPlainHighlightSpan();
    }

    if (hasSyntax) {
      final syntaxSpans = _syntaxHighlightedSpans();
      if (syntaxSpans.isEmpty) return TextSpan(text: widget.text, style: widget.style);
      return TextSpan(style: widget.style, children: syntaxSpans);
    }

    return TextSpan(text: widget.text, style: widget.style);
  }

  TextSpan _buildPlainHighlightSpan() {
    if (_query.isEmpty || _matches.isEmpty) {
      return TextSpan(text: widget.text, style: widget.style);
    }

    final children = <InlineSpan>[];
    var lastEnd = 0;

    for (var i = 0; i < _matches.length; i++) {
      final match = _matches[i];

      if (match.start > lastEnd) {
        children.add(TextSpan(
          text: widget.text.substring(lastEnd, match.start),
          style: widget.style,
        ));
      }

      final isActive = i == _activeIndex;
      children.add(TextSpan(
        text: widget.text.substring(match.start, match.end),
        style: widget.style.copyWith(
          backgroundColor: isActive
              ? TColors.yellow
              : TColors.yellow.withValues(alpha: 0.3),
          color: isActive ? TColors.background : null,
        ),
      ));

      lastEnd = match.end;
    }

    if (lastEnd < widget.text.length) {
      children.add(TextSpan(
        text: widget.text.substring(lastEnd),
        style: widget.style,
      ));
    }

    return TextSpan(children: children);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.searchActive) _buildSearchBar(),
        Expanded(
          child: _buildContent(),
        ),
      ],
    );
  }

  Widget _buildContent() {
    final hasSyntax = widget.syntaxLanguage != null;
    final isSearching = widget.searchActive && _query.isNotEmpty;

    if (hasSyntax || isSearching) {
      return SingleChildScrollView(
        key: _contentKey,
        controller: _scrollController,
        padding: widget.padding,
        child: SelectionArea(
          child: RichText(
            text: _buildSpan(),
            softWrap: true,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      key: _contentKey,
      controller: _scrollController,
      padding: widget.padding,
      child: SelectableText(widget.text, style: widget.style),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: TColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.search, size: 14, color: TColors.mutedText),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              style: const TextStyle(
                color: TColors.text,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
              decoration: const InputDecoration(
                hintText: 'find...',
                hintStyle: TextStyle(
                  color: TColors.mutedText,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: _onQueryChanged,
            ),
          ),
          if (_matches.isNotEmpty) ...[
            Text(
              '${_activeIndex + 1}/${_matches.length}',
              style: const TextStyle(
                color: TColors.mutedText,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: _prevMatch,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.keyboard_arrow_up,
                    size: 20, color: TColors.mutedText),
              ),
            ),
            GestureDetector(
              onTap: _nextMatch,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.keyboard_arrow_down,
                    size: 20, color: TColors.mutedText),
              ),
            ),
          ],
          GestureDetector(
            onTap: () {
              _resetSearch();
              widget.onClose?.call();
            },
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.close, size: 18, color: TColors.red),
            ),
          ),
        ],
      ),
    );
  }
}
