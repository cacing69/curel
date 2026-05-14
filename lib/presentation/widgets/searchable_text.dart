import 'dart:math' as math;

import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' show highlight, Node;

class SearchableText extends StatefulWidget {
  final String text;
  final bool searchActive;
  final TextStyle style;
  final EdgeInsetsGeometry padding;
  final String? syntaxLanguage;
  final Map<String, TextStyle>? syntaxTheme;
  final VoidCallback? onClose;

  SearchableText({
    required this.text,
    this.searchActive = false,
    TextStyle? style,
    EdgeInsetsGeometry? padding,
    this.syntaxLanguage,
    this.syntaxTheme,
    this.onClose,
    super.key,
  }) : style = style ?? TextStyle(
         fontFamily: 'monospace',
         fontSize: 12,
         color: TColors.text,
       ),
       padding = padding ?? EdgeInsets.all(4);

  @override
  State<SearchableText> createState() => _SearchableTextState();
}

class _SearchableTextState extends State<SearchableText> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  String _query = '';
  List<TextRange> _matches = [];
  int _activeIndex = 0;

  String? _cachedSyntaxText;
  String? _cachedSyntaxLanguage;
  List<TextSpan>? _cachedSyntaxFlats;

  List<List<TextSpan>> _lines = [];
  List<int> _lineOffsets = [];

  @override
  void initState() {
    super.initState();
    _rebuildLines();
  }

  @override
  void didUpdateWidget(covariant SearchableText oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.text != oldWidget.text) {
      _matches = _findAllMatches(widget.text, _query);
      if (_matches.isNotEmpty && _activeIndex >= _matches.length) {
        _activeIndex = 0;
      }
      _rebuildLines();
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
    _rebuildLines();
    if (matches.isNotEmpty) {
      _scrollToMatch(0);
    }
  }

  void _nextMatch() {
    if (_matches.isEmpty) return;
    final next = (_activeIndex + 1) % _matches.length;
    setState(() => _activeIndex = next);
    _rebuildLines();
    _scrollToMatch(next);
  }

  void _prevMatch() {
    if (_matches.isEmpty) return;
    final prev = (_activeIndex - 1 + _matches.length) % _matches.length;
    setState(() => _activeIndex = prev);
    _rebuildLines();
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

  int _lineIndexForOffset(int offset) {
    if (_lineOffsets.isEmpty) return 0;
    for (var i = _lineOffsets.length - 1; i >= 0; i--) {
      if (_lineOffsets[i] <= offset) return i;
    }
    return 0;
  }

  void _scrollToMatch(int index) {
    if (index >= _matches.length || _matches.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final match = _matches[index];
      final lineIdx = _lineIndexForOffset(match.start);
      final maxScroll = _scrollController.position.maxScrollExtent;
      final itemHeight = 18.0;
      final target = math.max(0.0, lineIdx * itemHeight - 60);
      _scrollController.animateTo(
        target.clamp(0.0, maxScroll),
        duration: Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    });
  }

  void _rebuildLines() {
    final flats = _computeFlatSpans();
    _lines = _splitSpansByNewlines(flats);
    _lineOffsets = _computeLineOffsets();
  }

  List<int> _computeLineOffsets() {
    final offsets = <int>[0];
    final text = widget.text;
    for (var i = 0; i < text.length; i++) {
      if (text[i] == '\n') {
        offsets.add(i + 1);
      }
    }
    return offsets;
  }

  List<TextSpan> _computeFlatSpans() {
    final isSearching = widget.searchActive && _query.isNotEmpty;
    final hasSyntax = widget.syntaxLanguage != null;

    if (!hasSyntax && !isSearching) {
      final spans = <TextSpan>[];
      _splitPlainText(spans, widget.text, 0, widget.text.length);
      return spans;
    }

    if (hasSyntax && !isSearching) {
      final syntaxSpans = _syntaxHighlightedFlatSpans();
      if (syntaxSpans.isEmpty) {
        final spans = <TextSpan>[];
        _splitPlainText(spans, widget.text, 0, widget.text.length);
        return spans;
      }
      return syntaxSpans;
    }

    final baseSpans = hasSyntax
        ? _syntaxHighlightedFlatSpans()
        : _plainFlats();

    if (isSearching && _query.isNotEmpty && _matches.isNotEmpty) {
      return _applySearchHighlight(baseSpans);
    }

    final theme = widget.syntaxTheme ?? syntaxTheme;
    final defaultColor = theme['root']?.color ?? TColors.text;
    return baseSpans.isEmpty
        ? [TextSpan(text: widget.text, style: TextStyle(color: defaultColor))]
        : baseSpans;
  }

  List<TextSpan> _plainFlats() {
    final spans = <TextSpan>[];
    _splitPlainText(spans, widget.text, 0, widget.text.length);
    return spans;
  }

  void _splitPlainText(List<TextSpan> into, String text, int from, int to) {
    final slice = text.substring(from, math.min(to, text.length));
    final parts = slice.split('\n');
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) into.add(TextSpan(text: '\n'));
      if (parts[i].isNotEmpty) {
        into.add(TextSpan(text: parts[i]));
      }
    }
  }

  List<TextSpan> _applySearchHighlight(List<TextSpan> baseSpans) {
    final theme = widget.syntaxTheme ?? syntaxTheme;
    final defaultColor = theme['root']?.color ?? TColors.text;
    final flatSpans = baseSpans.toList();

    if (_query.isEmpty || _matches.isEmpty) {
      return flatSpans;
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
      for (final span in matchSpans) {
        final spanColor = span.style?.color ?? defaultColor;
        children.add(TextSpan(
          text: span.text,
          style: TextStyle(
            color: isActive ? TColors.background : spanColor,
            backgroundColor: isActive
                ? TColors.yellow
                : TColors.yellow.withValues(alpha: 0.3),
          ),
        ));
      }

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      children.addAll(_sliceSpans(flatSpans, lastEnd, text.length));
    }

    final result = <TextSpan>[];
    for (final c in children) {
      if (c is TextSpan) result.add(c);
    }
    return result;
  }

  List<TextSpan> _sliceSpans(List<TextSpan> spans, int from, int to) {
    final result = <TextSpan>[];
    var pos = 0;

    for (final span in spans) {
      final t = span.text ?? '';
      if (t.isEmpty) continue;
      final spanStart = pos;
      final spanEnd = pos + t.length;

      if (spanEnd <= from || spanStart >= to) {
        pos = spanEnd;
        continue;
      }

      final overlapStart = math.max(spanStart, from) - pos;
      final overlapEnd = math.min(spanEnd, to) - pos;
      final slicedText = t.substring(overlapStart, overlapEnd);

      if (slicedText.isNotEmpty) {
        result.add(TextSpan(text: slicedText, style: span.style));
      }

      pos = spanEnd;
    }

    return result;
  }

  List<TextSpan> _syntaxHighlightedFlatSpans() {
    if (widget.syntaxLanguage == null) return [];
    if (_cachedSyntaxFlats != null &&
        _cachedSyntaxText == widget.text &&
        _cachedSyntaxLanguage == widget.syntaxLanguage) {
      return _cachedSyntaxFlats!;
    }
    final result = highlight.parse(widget.text, language: widget.syntaxLanguage);
    if (result.nodes == null) {
      _cachedSyntaxFlats = [];
      _cachedSyntaxText = widget.text;
      _cachedSyntaxLanguage = widget.syntaxLanguage;
      return [];
    }
    _cachedSyntaxFlats = _convertSyntaxNodes(result.nodes!);
    _cachedSyntaxText = widget.text;
    _cachedSyntaxLanguage = widget.syntaxLanguage;
    return _cachedSyntaxFlats!;
  }

  List<TextSpan> _convertSyntaxNodes(List<Node> nodes) {
    final theme = widget.syntaxTheme ?? syntaxTheme;
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

    final flat = <TextSpan>[];
    void flatten(TextSpan span) {
      if (span.text != null && span.text!.isNotEmpty) {
        flat.add(TextSpan(text: span.text, style: span.style));
      }
      if (span.children != null) {
        for (final c in span.children!) {
          if (c is TextSpan) flatten(c);
        }
      }
    }
    for (final span in spans) {
      flatten(span);
    }
    return flat;
  }

  List<List<TextSpan>> _splitSpansByNewlines(List<TextSpan> spans) {
    final lines = <List<TextSpan>>[[]];
    for (final span in spans) {
      final t = span.text ?? '';
      if (!t.contains('\n')) {
        lines.last.add(span);
        continue;
      }
      final parts = t.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) lines.add([]);
        if (parts[i].isNotEmpty) {
          lines.last.add(TextSpan(text: parts[i], style: span.style));
        }
      }
    }
    if (lines.last.isEmpty && lines.length > 1) {
      lines.removeLast();
    }
    return lines;
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
      return ListView.builder(
        controller: _scrollController,
        padding: widget.padding,
        itemCount: _lines.length,
        itemBuilder: (context, index) {
          final lineSpans = _lines[index];
          return SelectionArea(
            child: Text.rich(
              TextSpan(
                style: widget.style,
                children: lineSpans,
              ),
              softWrap: false,
            ),
          );
        },
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: widget.padding,
      itemCount: _lines.length,
      itemBuilder: (context, index) {
        final lineSpans = _lines[index];
        return SelectableText.rich(
          TextSpan(
            style: widget.style,
            children: lineSpans,
          ),
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: TColors.surface,
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.search, size: 14, color: TColors.mutedText),
          SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              style: TextStyle(
                color: TColors.text,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
              decoration: InputDecoration(
                hintText: 'find...',
                hintStyle: TextStyle(
                  color: TColors.mutedText,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: _onQueryChanged,
            ),
          ),
          if (_matches.isNotEmpty) ...[
            Text(
              '${_activeIndex + 1}/${_matches.length}',
              style: TextStyle(
                color: TColors.mutedText,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
            SizedBox(width: 4),
            GestureDetector(
              onTap: _activeIndex > 0 ? _prevMatch : null,
              child: Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.keyboard_arrow_up,
                  size: 20,
                  color: _activeIndex > 0
                      ? TColors.mutedText
                      : TColors.mutedText.withValues(alpha: 0.3),
                ),
              ),
            ),
            GestureDetector(
              onTap: _activeIndex < _matches.length - 1 ? _nextMatch : null,
              child: Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.keyboard_arrow_down,
                  size: 20,
                  color: _activeIndex < _matches.length - 1
                      ? TColors.mutedText
                      : TColors.mutedText.withValues(alpha: 0.3),
                ),
              ),
            ),
          ],
          GestureDetector(
            onTap: () {
              _resetSearch();
              widget.onClose?.call();
            },
            child: Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.close, size: 18, color: TColors.red),
            ),
          ),
        ],
      ),
    );
  }
}
