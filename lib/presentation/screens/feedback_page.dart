import 'dart:convert';

import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class FeedbackPage extends StatefulWidget {
  final String? projectId;
  final String? projectName;
  final String? requestPath;

  const FeedbackPage({
    this.projectId,
    this.projectName,
    this.requestPath,
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
  static const _webhookUrl =
      'https://discord.com/api/webhooks/1502746030901559517/5jl8A-L4t63I1AuHWZIMa4VvrOTqZiSqwdmi3sf3saCj45avfrGdrlzDf6sw0_Anz-xZ';

  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  final _stepsController = TextEditingController();
  final _expectedController = TextEditingController();
  final _actualController = TextEditingController();
  final _contactController = TextEditingController();

  var _category = 'bug';
  var _sending = false;
  var _version = '';
  var _buildNumber = '';
  final _images = <_PickedImage>[];

  @override
  void initState() {
    super.initState();
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
      for (var i = 0; i < _images.length; i++) {
        final img = _images[i];
        attachments.add({'id': i, 'filename': img.name});
        formMap['files[$i]'] = MultipartFile.fromBytes(img.bytes, filename: img.name);
      }
      if (attachments.isNotEmpty) {
        payload['attachments'] = attachments;
        final first = _images.first;
        (payload['embeds'] as List).first['image'] = {
          'url': 'attachment://${first.name}',
        };
      }
      formMap['payload_json'] = jsonEncode(payload);

      final dio = Dio();
      final res = await dio.post(
        _webhookUrl,
        data: FormData.fromMap(formMap),
        options: Options(contentType: 'multipart/form-data'),
      );

      if (res.statusCode != 200 && res.statusCode != 204) {
        throw Exception('send failed: ${res.statusCode}');
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

  Widget _buildHeader(BuildContext context) {
    return Container(
      color: TColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: _sending ? null : () => Navigator.of(context).pop(),
            child: const Icon(
              Icons.arrow_back,
              size: 18,
              color: TColors.mutedText,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
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

  Widget _buildSection({
    required String label,
    required String description,
    required TextEditingController controller,
    int maxLines = 1,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: TColors.cyan,
            fontFamily: 'monospace',
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          description,
          style: const TextStyle(
            color: TColors.mutedText,
            fontFamily: 'monospace',
            fontSize: 11,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: TColors.surface,
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            minLines: 1,
            cursorColor: TColors.green,
            style: const TextStyle(
              color: TColors.foreground,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
                fontSize: 13,
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
    );
  }

  Widget _buildCategorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          style: const TextStyle(
            color: TColors.cyan,
            fontFamily: 'monospace',
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
          decoration: const InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'what type of feedback is this?',
          style: TextStyle(
            color: TColors.mutedText,
            fontFamily: 'monospace',
            fontSize: 11,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          color: TColors.surface,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _category,
              dropdownColor: TColors.surface,
              iconEnabledColor: TColors.mutedText,
              items: const [
                DropdownMenuItem(value: 'bug', child: Text('bug')),
                DropdownMenuItem(value: 'suggestion', child: Text('suggestion')),
                DropdownMenuItem(value: 'question', child: Text('question')),
              ],
              onChanged: _sending
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() => _category = v);
                    },
              style: const TextStyle(
                color: TColors.foreground,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAttachmentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'attachments',
          style: TextStyle(
            color: TColors.cyan,
            fontFamily: 'monospace',
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'attach up to 3 images (max 8mb each).',
          style: TextStyle(
            color: TColors.mutedText,
            fontFamily: 'monospace',
            fontSize: 11,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            TermButton(
              icon: Icons.folder_open,
              label: 'pick images',
              onTap: _sending ? null : _pickImages,
              accent: true,
            ),
            const SizedBox(width: 8),
            TermButton(
              icon: Icons.refresh,
              label: 'clear',
              onTap: _sending ? null : () => setState(() => _images.clear()),
            ),
            const SizedBox(width: 10),
            Text(
              '${_images.length}/3',
              style: const TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ],
        ),
        if (_images.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _images.length; i++)
                Stack(
                  children: [
                    Container(
                      width: 110,
                      height: 80,
                      decoration: BoxDecoration(
                        border: Border.all(color: TColors.border),
                        color: TColors.surface,
                      ),
                      child: Image.memory(
                        _images[i].bytes,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: _sending
                            ? null
                            : () => setState(() => _images.removeAt(i)),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: TColors.surface,
                            border: Border.all(color: TColors.border),
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: TColors.mutedText,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }

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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'tell us what happened. include steps and screenshots if possible.',
                      style: TextStyle(
                        color: TColors.foreground,
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildCategorySection(),
                    const SizedBox(height: 20),
                    _buildSection(
                      label: 'title',
                      description: 'short summary of your feedback.',
                      controller: _titleController,
                      hint: 'short summary',
                    ),
                    const SizedBox(height: 20),
                    _buildSection(
                      label: 'message',
                      description: 'describe the issue / suggestion. required.',
                      controller: _messageController,
                      maxLines: 6,
                      hint: 'write here...',
                    ),
                    const SizedBox(height: 20),
                    _buildSection(
                      label: 'steps',
                      description: 'how to reproduce. optional.',
                      controller: _stepsController,
                      maxLines: 4,
                      hint: '1) ... 2) ...',
                    ),
                    const SizedBox(height: 20),
                    _buildSection(
                      label: 'expected',
                      description: 'what you expected to happen. optional.',
                      controller: _expectedController,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 20),
                    _buildSection(
                      label: 'actual',
                      description: 'what actually happened. optional.',
                      controller: _actualController,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 20),
                    _buildSection(
                      label: 'contact',
                      description: 'how we can reach you. optional.',
                      controller: _contactController,
                      hint: 'email / discord / other',
                    ),
                    const SizedBox(height: 20),
                    _buildAttachmentsSection(),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        TermButton(
                          icon: Icons.send,
                          label: _sending ? 'sending...' : 'send',
                          onTap: _sending ? null : _send,
                          accent: true,
                        ),
                        const SizedBox(width: 8),
                        TermButton(
                          icon: Icons.refresh,
                          label: 'reset fields',
                          onTap: _sending
                              ? null
                              : () {
                                  _titleController.clear();
                                  _messageController.clear();
                                  _stepsController.clear();
                                  _expectedController.clear();
                                  _actualController.clear();
                                  _contactController.clear();
                                  setState(() => _images.clear());
                                },
                        ),
                        const Spacer(),
                        if (_sending)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              color: TColors.green,
                              strokeWidth: 2,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
