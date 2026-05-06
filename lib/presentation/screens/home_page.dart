import 'package:Curel/data/models/curl_response.dart';
import 'package:Curel/presentation/screens/about_page.dart';
import 'package:Curel/data/services/curl_http_client.dart';
import 'package:Curel/domain/services/clipboard_service.dart';
import 'package:Curel/domain/services/curl_parser_service.dart';
import 'package:Curel/presentation/theme/terminal_colors.dart';
import 'package:Curel/presentation/widgets/response_viewer.dart';
import 'package:Curel/presentation/widgets/term_button.dart';
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
  final _curlController = TextEditingController();
  CurlResponse? _response;
  bool _isLoading = false;
  String? _error;
  var _selectedTab = ResponseTab.body;
  bool _showHtmlPreview = false;
  bool _searchActive = false;

  @override
  void dispose() {
    _curlController.dispose();
    super.dispose();
  }

  Future<void> _executeCurl() async {
    final text = _curlController.text.trim();
    if (text.isEmpty || !text.startsWith('curl')) {
      setState(() {
        _error = 'error: command must start with "curl"';
        _response = null;
        _showHtmlPreview = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _response = null;
      _error = null;
      _showHtmlPreview = false;
    });

    try {
      final curl = parseCurl(text);
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Prompt input block
            Container(
              color: TColors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 0),
                    child: Text(
                      '❯ ',
                      style: TextStyle(
                        color: TColors.green,
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _curlController,
                      maxLines: null,
                      minLines: 3,
                      cursorColor: TColors.green,
                      style: const TextStyle(
                        color: TColors.text,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'paste or type a curl command...',
                        hintStyle: TextStyle(
                          color: TColors.mutedText,
                          fontFamily: 'monospace',
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
              ),
            ),
            // Action buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  // TermButton(
                  //   icon: Icons.history,
                  //   label: 'History',
                  //   onTap: () {},
                  // ),
                  // const SizedBox(width: 6),
                  TermButton(
                    icon: Icons.content_paste,
                    label: 'Paste',
                    onTap: _paste,
                  ),
                  const SizedBox(width: 6),
                  TermButton(
                    icon: Icons.info_outline,
                    label: 'About',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AboutPage()),
                    ),
                  ),
                  const Spacer(),
                  TermButton(
                    label: 'Execute',
                    onTap: _isLoading ? null : _executeCurl,
                    accent: true,
                  ),
                ],
              ),
            ),
            // Response bar
            if (_response != null || _error != null) ...[
              Container(height: 1, color: TColors.border),
              if (_response != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              const Text(
                                'response',
                                style: TextStyle(
                                  color: TColors.purple,
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${_response!.statusCode ?? '-'}',
                                style: TextStyle(
                                  color:
                                      (_response!.statusCode ?? 0) >= 200 &&
                                          (_response!.statusCode ?? 0) < 300
                                      ? TColors.green
                                      : TColors.red,
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _response!.contentTypeLabel,
                                style: const TextStyle(
                                  color: TColors.cyan,
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(width: 12),
                              _FlatTab(
                                label: 'headers',
                                selected: _selectedTab == ResponseTab.headers,
                                onTap: () => setState(() {
                                  _selectedTab = ResponseTab.headers;
                                  _showHtmlPreview = false;
                                }),
                              ),
                              const SizedBox(width: 4),
                              _FlatTab(
                                label: 'body',
                                selected:
                                    _selectedTab == ResponseTab.body &&
                                    !_showHtmlPreview,
                                onTap: () => setState(() {
                                  _selectedTab = ResponseTab.body;
                                  _showHtmlPreview = false;
                                }),
                              ),
                              if (_response!.isHtml) ...[
                                const SizedBox(width: 4),
                                _FlatTab(
                                  label: 'preview',
                                  selected: _showHtmlPreview,
                                  onTap: () => setState(() {
                                    _selectedTab = ResponseTab.body;
                                    _showHtmlPreview = true;
                                    _searchActive = false;
                                  }),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _searchActive = !_searchActive),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Icon(
                            _searchActive ? Icons.search_off : Icons.search,
                            size: 16,
                            color: _searchActive
                                ? TColors.green
                                : TColors.mutedText,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () =>
                            openFullscreenResponse(context, _response!),
                        child: const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.fullscreen,
                            size: 16,
                            color: TColors.mutedText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Container(height: 1, color: TColors.border),
            ],
            // Response content
            Expanded(
              child: ResponseViewer(
                isLoading: _isLoading,
                response: _response,
                error: _error,
                selectedTab: _selectedTab,
                showHtmlPreview: _showHtmlPreview,
                searchActive: _searchActive,
                onCloseSearch: () => setState(() => _searchActive = false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlatTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FlatTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? TColors.green : Colors.transparent,
              width: 1,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            color: selected ? TColors.foreground : TColors.mutedText,
          ),
        ),
      ),
    );
  }
}
