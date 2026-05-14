import 'dart:convert';
import 'dart:io';

import 'package:curel/domain/providers/services.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/chunked_text_viewer.dart';
import 'package:curel/presentation/widgets/searchable_text.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

class FilePreviewPage extends ConsumerStatefulWidget {
  final String path;
  final String name;
  final String? relativePath;

  const FilePreviewPage({
    required this.path,
    required this.name,
    this.relativePath,
    super.key,
  });

  @override
  ConsumerState<FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends ConsumerState<FilePreviewPage> {
  String? _content;
  String? _error;
  bool _loading = true;
  bool _tooLarge = false;
  int _fileSize = 0;
  bool _searchActive = false;

  static const _maxPreviewBytes = 512 * 1024;

  @override
  void initState() {
    super.initState();
    _checkAndLoad();
  }

  Future<void> _checkAndLoad() async {
    try {
      final file = File(widget.path);
      if (!await file.exists()) {
        if (mounted) setState(() { _error = 'file not found'; _loading = false; });
        return;
      }
      final size = await file.length();
      _fileSize = size;
      if (size > _maxPreviewBytes) {
        if (mounted) setState(() { _tooLarge = true; _loading = false; });
        return;
      }
      await _loadContent();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadContent() async {
    try {
      var content = await ref.read(fileSystemProvider).readFile(widget.path);
      if (_detectLanguage(widget.name) == 'json') {
        try {
          content = const JsonEncoder.withIndent('  ').convert(jsonDecode(content));
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _content = content;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  void _reload() {
    setState(() {
      _loading = true;
      _error = null;
      _tooLarge = false;
      _content = null;
      _searchActive = false;
    });
    _checkAndLoad();
  }

  String? _detectLanguage(String name) {
    final ext = p.extension(name).toLowerCase();
    return switch (ext) {
      '.curl' || '.sh' => 'bash',
      '.json' => 'json',
      '.yaml' || '.yml' => 'yaml',
      '.xml' => 'xml',
      '.env' || '.ini' => 'ini',
      '.sql' => 'sql',
      '.properties' => 'properties',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Container(height: 1, color: TColors.border),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: TColors.surface,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Icon(Icons.arrow_back, size: 18, color: TColors.mutedText),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.name,
                  style: TextStyle(
                    color: TColors.foreground,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.relativePath != null)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _buildBreadcrumbSegments(),
                    ),
                  ),
              ],
            ),
          ),
          if (_content != null) ...[
            SizedBox(width: 4),
            GestureDetector(
              onTap: _searchActive
                  ? () => setState(() => _searchActive = false)
                  : () => setState(() => _searchActive = true),
              child: Icon(
                _searchActive ? Icons.search_off : Icons.search,
                size: 16,
                color: _searchActive ? TColors.green : TColors.mutedText,
              ),
            ),
          ],
          SizedBox(width: 4),
          GestureDetector(
            onTap: () => Share.shareXFiles([XFile(widget.path)]),
            child: Icon(Icons.open_in_new, size: 16, color: TColors.mutedText),
          ),
          if (_content != null) ...[
            SizedBox(width: 4),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: _content!));
                showTerminalToast(context, 'copied');
              },
              child: Icon(Icons.copy, size: 16, color: TColors.mutedText),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildBreadcrumbSegments() {
    if (widget.relativePath == null) return [];
    final parts = widget.relativePath!.split('/');
    final widgets = <Widget>[];
    for (int i = 0; i < parts.length; i++) {
      final isLast = i == parts.length - 1;
      if (i > 0) {
        widgets.add(Text(
          '/',
          style: TextStyle(
            color: TColors.mutedText,
            fontFamily: 'monospace',
            fontSize: 9,
          ),
        ));
      }
      widgets.add(GestureDetector(
        onTap: isLast ? null : () => Navigator.of(context).pop(),
        child: Text(
          parts[i],
          style: TextStyle(
            color: isLast ? TColors.foreground : TColors.green,
            fontFamily: 'monospace',
            fontSize: 9,
          ),
        ),
      ));
    }
    return widgets;
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: TerminalLoader());
    }

    if (_tooLarge) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber, size: 28, color: TColors.orange),
              SizedBox(height: 12),
              Text(
                'file too large',
                style: TextStyle(
                  color: TColors.foreground,
                  fontSize: 13,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 6),
              Text(
                '${(_fileSize / 1024).toStringAsFixed(0)}k · max ${_maxPreviewBytes ~/ 1024}k',
                style: TextStyle(
                  color: TColors.mutedText,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TermButton(
                    icon: Icons.open_in_new,
                    label: 'open external',
                    onTap: () => Share.shareXFiles([XFile(widget.path)]),
                  ),
                  SizedBox(width: 8),
                  TermButton(
                    icon: Icons.visibility,
                    label: 'load anyway',
                    onTap: () {
                      setState(() { _loading = true; _tooLarge = false; });
                      _loadContent();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(
                  color: TColors.red,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            SizedBox(height: 8),
            TermButton(icon: Icons.refresh, label: 'retry', onTap: _reload),
          ],
        ),
      );
    }

    if (_content == null || _content!.isEmpty) {
      return Center(
        child: Text(
          'empty',
          style: TextStyle(
            color: TColors.mutedText.withValues(alpha: 0.5),
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
      );
    }

    final lang = _detectLanguage(widget.name);

    if (_searchActive) {
      return SearchableText(
        text: _content!,
        searchActive: true,
        syntaxLanguage: lang,
        onClose: () => setState(() => _searchActive = false),
      );
    }

    return ChunkedTextViewer(
      text: _content!,
      language: lang,
      onRefresh: _reload,
    );
  }
}
