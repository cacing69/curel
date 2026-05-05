import 'package:Curel/data/models/curl_response.dart';
import 'package:Curel/data/services/curl_http_client.dart';
import 'package:Curel/domain/services/clipboard_service.dart';
import 'package:Curel/domain/services/curl_parser_service.dart';
import 'package:Curel/presentation/widgets/response_viewer.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

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
    final style = context.theme.style;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          FTextField.multiline(
            control: FTextFieldControl.managed(controller: _curlController),
            label: const Text('cURL'),
          ),
          Row(
            spacing: 5,
            children: [
              FButton.icon(onPress: () {}, child: const Icon(FIcons.history)),
              FButton.icon(
                onPress: _paste,
                child: const Icon(FIcons.clipboardPaste),
              ),

              Expanded(
                child: FButton(
                  mainAxisSize: .max,
                  onPress: _isLoading ? null : _executeCurl,
                  child: const Text('Execute'),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Text('Response:'),
              if (_response != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: context.theme.colors.primary,
                    borderRadius: style.borderRadius.sm,
                  ),
                  child: Text(
                    _response!.contentTypeLabel,
                    style: TextStyle(
                      color: context.theme.colors.primaryForeground,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: context.theme.colors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: ResponseViewer(
                isLoading: _isLoading,
                response: _response,
                error: _error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
