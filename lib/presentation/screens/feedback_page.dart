import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:package_info_plus/package_info_plus.dart';

String _obfuscated() {
  const a = [104, 116, 116, 112, 115, 58, 47, 47, 100, 105, 115, 99, 111];
  const b = [114, 100, 46, 99, 111, 109, 47, 97, 112, 105, 47, 119, 101];
  const c = [98, 104, 111, 111, 107, 115, 47];
  const d = [49, 53, 48, 50, 55, 52, 54, 48, 51, 48, 57, 48, 49, 53, 53];
  const e = [57, 53, 49, 55, 47];
  const f = [
    53, 106, 108, 56, 65, 45, 76, 52, 116, 54, 51, 73, 49, 65, 117, 72,
    87, 90, 73, 77, 97, 52, 86, 118, 114, 79, 84, 113, 90, 105, 83, 113,
    119, 100, 109, 105, 51, 115, 102, 51, 115, 97, 67, 106, 52, 53, 97,
    118, 102, 114, 71, 100, 114, 108, 122, 68, 102, 54, 115, 119, 48, 95,
    65, 110, 122, 45, 120, 90,
  ];
  return String.fromCharCodes([...a, ...b, ...c, ...d, ...e, ...f]);
}

class FeedbackPage extends StatefulWidget {
  final String? projectId;
  final String? projectName;
  final String? requestPath;
  final String? initialTitle;
  final String? initialMessage;

  const FeedbackPage({
    this.projectId,
    this.projectName,
    this.requestPath,
    this.initialTitle,
    this.initialMessage,
    super.key,
  });

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _PickedImage {
  final String name;
  final Uint8List bytes;

  const _PickedImage({required this.name, required this.bytes});
}

class _FeedbackPageState extends State<FeedbackPage> {
  static final _webhookUrl = _obfuscated();

  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  final _stepsController = TextEditingController();
  final _expectedController = TextEditingController();
  final _actualController = TextEditingController();
  final _contactController = TextEditingController();

  var _category = 'bug';
  var _sending = false;
  var _showDetails = false;
  var _version = '';
  var _buildNumber = '';
  final _images = <_PickedImage>[];

  @override
  void initState() {
    super.initState();
    if (widget.initialTitle != null) {
      _titleController.text = widget.initialTitle!;
    }
    if (widget.initialMessage != null) {
      _messageController.text = widget.initialMessage!;
    }
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() {
        _version = info.version;
        _buildNumber = info.buildNumber;
      });
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    _stepsController.dispose();
    _expectedController.dispose();
    _actualController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<_PickedImage> _compressImage(_PickedImage img) async {
    final compressed = await FlutterImageCompress.compressWithList(
      img.bytes,
      minHeight: 1,
      minWidth: 720,
      quality: 80,
    );
    return _PickedImage(
      name: img.name.replaceFirst(RegExp(r'\.\w+$'), '.jpg'),
      bytes: Uint8List.fromList(compressed),
    );
  }

  String _truncate(String s, int max) {
    final trimmed = s.trim();
    if (trimmed.length <= max) return trimmed;
    return '${trimmed.substring(0, max - 1)}…';
  }

  Future<void> _pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;
    final picked = <_PickedImage>[];
    for (final f in result.files) {
      final bytes = f.bytes;
      if (bytes == null) continue;
      if (bytes.lengthInBytes > 8 * 1024 * 1024) {
        if (mounted) showTerminalToast(context, 'image too large (>8mb): ${f.name}');
        continue;
      }
      picked.add(_PickedImage(name: f.name, bytes: bytes));
    }
    if (picked.isEmpty) return;
    if (!mounted) return;
    setState(() {
      for (final img in picked) {
        if (_images.length >= 3) break;
        _images.add(img);
      }
    });
  }

  Future<void> _send() async {
    if (_sending) return;
    final title = _titleController.text.trim();
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      showTerminalToast(context, 'message is required');
      return;
    }

    setState(() => _sending = true);
    try {
      final appInfo = _version.isEmpty
          ? 'unknown'
          : (_buildNumber.isNotEmpty ? 'v$_version ($_buildNumber)' : 'v$_version');
      final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
      final now = DateTime.now().toIso8601String();

      final fields = <Map<String, dynamic>>[
        {'name': 'category', 'value': _category, 'inline': true},
        {'name': 'app', 'value': appInfo, 'inline': true},
        {'name': 'platform', 'value': platform, 'inline': true},
      ];

      final project = widget.projectId == null
          ? 'none'
          : '${widget.projectName ?? 'project'} (${widget.projectId})';
      fields.add({'name': 'project', 'value': _truncate(project, 1000), 'inline': false});

      if (widget.requestPath != null && widget.requestPath!.trim().isNotEmpty) {
        fields.add({
          'name': 'request',
          'value': _truncate(widget.requestPath!, 1000),
          'inline': false,
        });
      }

      final contact = _contactController.text.trim();
      if (contact.isNotEmpty) {
        fields.add({'name': 'contact', 'value': _truncate(contact, 1000), 'inline': false});
      }

      final steps = _stepsController.text.trim();
      if (steps.isNotEmpty) {
        fields.add({'name': 'steps', 'value': _truncate(steps, 1000), 'inline': false});
      }

      final expected = _expectedController.text.trim();
      if (expected.isNotEmpty) {
        fields.add({'name': 'expected', 'value': _truncate(expected, 1000), 'inline': false});
      }

      final actual = _actualController.text.trim();
      if (actual.isNotEmpty) {
        fields.add({'name': 'actual', 'value': _truncate(actual, 1000), 'inline': false});
      }

      final payload = <String, dynamic>{
        'username': 'curel feedback',
        'content': 'feedback received',
        'embeds': [
          <String, dynamic>{
            'title': title.isEmpty ? 'feedback' : _truncate(title, 250),
            'description': _truncate(message, 3500),
            'color': 0x57F287,
            'fields': fields,
            'timestamp': now,
          },
        ],
      };

      final formMap = <String, dynamic>{};
      final attachments = <Map<String, dynamic>>[];
      final compressedImages = await Future.wait(_images.map(_compressImage));
      for (var i = 0; i < compressedImages.length; i++) {
        final img = compressedImages[i];
        attachments.add({'id': i, 'filename': img.name});
        formMap['files[$i]'] = img;
      }
      if (attachments.isNotEmpty) {
        payload['attachments'] = attachments;
        final first = _images.first;
        (payload['embeds'] as List).first['image'] = {
          'url': 'attachment://${first.name}',
        };
      }
      formMap['payload_json'] = jsonEncode(payload);

      final uri = Uri.parse(_webhookUrl);
      final client = HttpClient();
      final req = await client.postUrl(uri);
      final boundary = 'boundary_${DateTime.now().millisecondsSinceEpoch}';
      req.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');
      for (final entry in formMap.entries) {
        final val = entry.value;
        if (val is _PickedImage) {
          req.write('--$boundary\r\n');
          req.write('Content-Disposition: form-data; name="${entry.key}"; filename="${val.name}"\r\n');
          req.write('Content-Type: application/octet-stream\r\n\r\n');
          req.add(val.bytes);
        } else {
          req.write('--$boundary\r\n');
          req.write('Content-Disposition: form-data; name="${entry.key}"\r\n\r\n');
          req.write('$val\r\n');
        }
      }
      req.write('--$boundary--\r\n');
      final resp = await req.close();
      final resBody = await resp.transform(utf8.decoder).join();
      client.close();

      if (resp.statusCode != 200 && resp.statusCode != 204) {
        throw Exception('send failed: ${resp.statusCode} $resBody');
      }

      if (!mounted) return;
      showTerminalToast(context, 'sent');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      showTerminalToast(context, 'error: $e');
      setState(() => _sending = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Container(height: 1, color: TColors.border),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCategoryTabs(),
                    SizedBox(height: 12),
                    _buildField(
                      controller: _titleController,
                      hint: 'title',
                      maxLines: 1,
                    ),
                    SizedBox(height: 8),
                    _buildField(
                      controller: _messageController,
                      hint: 'describe the issue or suggestion...',
                      maxLines: 5,
                    ),
                    SizedBox(height: 8),
                    _buildAttachRow(),
                    if (_images.isNotEmpty) _buildImagePreviews(),
                    SizedBox(height: 8),
                    _buildDetailsToggle(),
                    if (_showDetails) ...[
                      SizedBox(height: 8),
                      _buildField(
                        controller: _stepsController,
                        hint: 'steps to reproduce (1) ... (2) ...',
                        maxLines: 3,
                      ),
                      SizedBox(height: 8),
                      _buildField(
                        controller: _expectedController,
                        hint: 'expected result',
                        maxLines: 2,
                      ),
                      SizedBox(height: 8),
                      _buildField(
                        controller: _actualController,
                        hint: 'actual result',
                        maxLines: 2,
                      ),
                      SizedBox(height: 8),
                      _buildField(
                        controller: _contactController,
                        hint: 'contact (email / discord)',
                        maxLines: 1,
                      ),
                    ],
                    SizedBox(height: 12),
                    _buildActions(),
                    SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      color: TColors.surface,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          GestureDetector(
            onTap: _sending ? null : () => Navigator.of(context).pop(),
            child: Icon(Icons.arrow_back, size: 18, color: TColors.mutedText),
          ),
          SizedBox(width: 8),
          Text(
            'feedback',
            style: TextStyle(
              color: TColors.foreground,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs() {
    const tabs = ['bug', 'suggestion', 'question'];
    return Row(
      children: tabs.map((t) {
        final active = _category == t;
        return Padding(
          padding: EdgeInsets.only(right: 4),
          child: GestureDetector(
            onTap: _sending ? null : () => setState(() => _category = t),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              color: active ? TColors.green.withValues(alpha: 0.15) : TColors.surface,
              child: Text(
                t,
                style: TextStyle(
                  color: active ? TColors.green : TColors.mutedText,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: TColors.surface,
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        minLines: 1,
        cursorColor: TColors.green,
        style: TextStyle(
          color: TColors.foreground,
          fontFamily: 'monospace',
          fontSize: 12,
        ),
        decoration: InputDecoration(
          hintText: hint,
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
      ),
    );
  }

  Widget _buildAttachRow() {
    return Container(
      color: TColors.surface,
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          GestureDetector(
            onTap: _sending ? null : _pickImages,
            child: Icon(Icons.attach_file, size: 16, color: TColors.cyan),
          ),
          SizedBox(width: 8),
          Text(
            _images.isEmpty ? 'attach images' : '${_images.length}/3',
            style: TextStyle(
              color: _images.isEmpty ? TColors.mutedText : TColors.cyan,
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
          if (_images.isNotEmpty) ...[
            const Spacer(),
            GestureDetector(
              onTap: _sending ? null : () => setState(() => _images.clear()),
              child: Icon(Icons.close, size: 14, color: TColors.mutedText),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImagePreviews() {
    return Container(
      color: TColors.surface,
      padding: EdgeInsets.fromLTRB(10, 4, 10, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < _images.length; i++)
            Stack(
              children: [
                Container(
                  width: 80,
                  height: 56,
                  decoration: BoxDecoration(
                    border: Border.all(color: TColors.border),
                    color: TColors.background,
                  ),
                  child: Image.memory(_images[i].bytes, fit: BoxFit.cover),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: _sending ? null : () => setState(() => _images.removeAt(i)),
                    child: Container(
                      padding: EdgeInsets.all(1),
                      color: TColors.surface,
                      child: Icon(Icons.close, size: 10, color: TColors.mutedText),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildDetailsToggle() {
    return GestureDetector(
      onTap: _sending ? null : () => setState(() => _showDetails = !_showDetails),
      child: Container(
        color: TColors.surface,
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Icon(
              _showDetails ? Icons.expand_less : Icons.expand_more,
              size: 14,
              color: TColors.mutedText,
            ),
            SizedBox(width: 6),
            Text(
              'details',
              style: TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
            SizedBox(width: 4),
            Text(
              '(optional)',
              style: TextStyle(
                color: TColors.mutedText.withValues(alpha: 0.5),
                fontFamily: 'monospace',
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        TermButton(
          icon: Icons.send,
          label: _sending ? 'sending...' : 'send',
          onTap: _sending ? null : _send,
          accent: true,
        ),
        const Spacer(),
        if (_sending)
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              color: TColors.green,
              strokeWidth: 2,
            ),
          ),
      ],
    );
  }
}
