import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class HtmlPreview extends StatefulWidget {
  final String html;

  const HtmlPreview({required this.html, super.key});

  @override
  State<HtmlPreview> createState() => _HtmlPreviewState();
}

class _HtmlPreviewState extends State<HtmlPreview> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()..loadHtmlString(widget.html);
  }

  @override
  void didUpdateWidget(covariant HtmlPreview old) {
    super.didUpdateWidget(old);
    if (old.html != widget.html) {
      _controller.loadHtmlString(widget.html);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
