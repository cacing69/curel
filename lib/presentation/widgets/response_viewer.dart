import 'package:Curel/data/models/curl_response.dart';
import 'package:Curel/presentation/widgets/html_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight2/themes/atom-one-dark.dart';
import 'package:forui/forui.dart';
import 'package:flutter_highlight2/flutter_highlight.dart';

class ResponseViewer extends StatelessWidget {
  final bool isLoading;
  final CurlResponse? response;
  final String? error;

  const ResponseViewer({
    this.isLoading = false,
    this.response,
    this.error,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (error != null) {
      return SingleChildScrollView(
        child: SelectableText(
          error!,
          style: TextStyle(color: context.theme.colors.error),
        ),
      );
    }

    if (response != null) {
      return _ResponseContent(response: response!);
    }

    return const Center(
      child: Text('No response yet', style: TextStyle(color: Colors.grey)),
    );
  }
}

class _ResponseContent extends StatefulWidget {
  final CurlResponse response;
  const _ResponseContent({required this.response});

  @override
  State<_ResponseContent> createState() => _ResponseContentState();
}

class _ResponseContentState extends State<_ResponseContent> {
  bool _showHtmlPreview = false;

  @override
  Widget build(BuildContext context) {
    return FTabs(
      expands: true,
      children: [
        FTabEntry(
          label: const Text('Headers'),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            child: SelectableText(
              widget.response.formatHeaders(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        FTabEntry(
          label: Text('Body${widget.response.isHtml ? ' / Preview' : ''}'),
          child: _buildBodyTab(),
        ),
      ],
    );
  }

  Widget _buildBodyTab() {
    if (widget.response.isHtml) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FButton(
              mainAxisSize: .min,
              onPress: () => setState(() => _showHtmlPreview = !_showHtmlPreview),
              child: Text(_showHtmlPreview ? 'Show Source' : 'Preview HTML'),
            ),
          ),
          Expanded(
            child: _showHtmlPreview
                ? HtmlPreview(html: widget.response.bodyText)
                : _buildHighlightedBody(),
          ),
        ],
      );
    }

    return _buildHighlightedBody();
  }

  Widget _buildHighlightedBody() {
    final lang = widget.response.highlightLanguage;

    if (lang != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: HighlightView(
          widget.response.bodyText,
          language: lang,
          theme: atomOneDarkTheme,
          textStyle: const TextStyle(fontSize: 12),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: SelectableText(
        widget.response.bodyText,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }
}
