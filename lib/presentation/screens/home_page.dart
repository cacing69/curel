import 'package:Curel/data/models/curl_response.dart';
import 'package:Curel/data/services/curl_http_client.dart';
import 'package:Curel/domain/services/clipboard_service.dart';
import 'package:Curel/domain/services/curl_parser_service.dart';
import 'package:Curel/presentation/theme/terminal_colors.dart';
import 'package:Curel/presentation/widgets/response_viewer.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  final CurlHttpClient httpClient;
  final ClipboardService clipboardService;

  const HomePage({
    required this.httpClient,
    required this.clipboardService,
    super.key,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _curlController = TextEditingController(
    text: 'curl -L https://www.google.com',
  );
  CurlResponse? _response;
  bool _isLoading = false;
  String? _error;
  var _selectedTab = ResponseTab.body;
  bool _showHtmlPreview = false;

  @override
  void dispose() {
    _curlController.dispose();
    super.dispose();
  }

  Future<void> _executeCurl() async {
    setState(() {
      _isLoading = true;
      _response = null;
      _error = null;
      _showHtmlPreview = false;
    });

    try {
      final curl = parseCurl(_curlController.text);
      final result = await widget.httpClient.execute(curl);
      setState(() => _response = result);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _paste() async {
    final text = await widget.clipboardService.paste();
    if (text != null) {
      setState(() => _curlController.text = text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _curlController,
                maxLines: 5,
                minLines: 3,
                style: const TextStyle(
                  color: TColors.text,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  hintText: '\$ curl ...',
                  hintStyle: TextStyle(color: TColors.mutedText.withValues(alpha: 0.5)),
                  prefixIcon: Text(
                    '\$ ',
                    style: const TextStyle(
                      color: TColors.accentText,
                      fontFamily: 'monospace',
                      fontSize: 14,
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 24),
                  filled: true,
                  fillColor: TColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: TColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: TColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: TColors.accentText),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _TermButton(
                    icon: Icons.history,
                    label: 'History',
                    onTap: () {},
                  ),
                  const SizedBox(width: 4),
                  _TermButton(
                    icon: Icons.content_paste,
                    label: 'Paste',
                    onTap: _paste,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _TermButton(
                      label: 'Execute',
                      onTap: _isLoading ? null : _executeCurl,
                      accent: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_response != null)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Text(
                        'Response:',
                        style: TextStyle(color: TColors.mutedText, fontSize: 12),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: TColors.accent.withValues(alpha:0.3),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          _response!.contentTypeLabel,
                          style: const TextStyle(
                            color: TColors.accentText,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _TabChip(
                        label: 'Headers',
                        selected: _selectedTab == ResponseTab.headers,
                        onTap: () => setState(() {
                          _selectedTab = ResponseTab.headers;
                          _showHtmlPreview = false;
                        }),
                      ),
                      const SizedBox(width: 4),
                      _TabChip(
                        label: 'Body',
                        selected: _selectedTab == ResponseTab.body &&
                            !_showHtmlPreview,
                        onTap: () => setState(() {
                          _selectedTab = ResponseTab.body;
                          _showHtmlPreview = false;
                        }),
                      ),
                      if (_response!.isHtml) ...[
                        const SizedBox(width: 4),
                        _TabChip(
                          label: 'Preview',
                          selected: _showHtmlPreview,
                          onTap: () => setState(() {
                            _selectedTab = ResponseTab.body;
                            _showHtmlPreview = true;
                          }),
                        ),
                      ],
                      const Spacer(),
                      GestureDetector(
                        onTap: () => openFullscreenResponse(context, _response!),
                        child: Icon(
                          Icons.fullscreen,
                          size: 16,
                          color: TColors.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: TColors.border),
                    borderRadius: BorderRadius.circular(4),
                    color: TColors.surface,
                  ),
                  padding: const EdgeInsets.all(8),
                  child: ResponseViewer(
                    isLoading: _isLoading,
                    response: _response,
                    error: _error,
                    selectedTab: _selectedTab,
                    showHtmlPreview: _showHtmlPreview,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? TColors.accent.withValues(alpha:0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: selected
              ? Border.all(color: TColors.accent.withValues(alpha:0.3))
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? TColors.accentText : TColors.mutedText,
          ),
        ),
      ),
    );
  }
}

class _TermButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback? onTap;
  final bool accent;

  const _TermButton({this.icon, required this.label, this.onTap, this.accent = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: accent
                ? TColors.accent.withValues(alpha:onTap == null ? 0.3 : 0.8)
                : TColors.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: accent ? TColors.accent : TColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: accent ? TColors.text : TColors.mutedText),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: accent
                      ? TColors.text
                      : (onTap == null ? TColors.mutedText.withValues(alpha:0.5) : TColors.mutedText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
