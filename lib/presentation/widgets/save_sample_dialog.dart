import 'package:curel/data/models/curl_response.dart';
import 'package:curel/domain/models/sample_model.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SaveSampleDialog extends ConsumerStatefulWidget {
  final CurlResponse response;
  final String projectId;
  final String requestRelativePath;

  const SaveSampleDialog({
    required this.response,
    required this.projectId,
    required this.requestRelativePath,
    super.key,
  });

  @override
  ConsumerState<SaveSampleDialog> createState() => _SaveSampleDialogState();
}

class _SaveSampleDialogState extends ConsumerState<SaveSampleDialog> {
  late TextEditingController _nameCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final code = widget.response.statusCode ?? 0;
    final group = code >= 200 && code < 300
        ? '2xx'
        : code >= 400 && code < 500
            ? '4xx'
            : code >= 500
                ? '5xx'
                : 'other';
    _nameCtrl = TextEditingController(
      text: '${group}_${code}_${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.response.statusCode ?? 0;
    final group = SampleMeta.groupFor(code);

    return AlertDialog(
      backgroundColor: TColors.background,
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: TColors.surface,
              child: Row(
                children: [
                  Icon(Icons.save, size: 16, color: TColors.purple),
                  SizedBox(width: 8),
                  Text(
                    'save sample response',
                    style: TextStyle(
                      color: TColors.foreground,
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(Icons.close, size: 16, color: TColors.mutedText),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: TColors.border),
            Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        'status: ',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: TColors.mutedText,
                        ),
                      ),
                      Text(
                        '$code',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: code >= 200 && code < 300
                              ? TColors.green
                              : TColors.red,
                        ),
                      ),
                      SizedBox(width: 16),
                      Text(
                        'group: ',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: TColors.mutedText,
                        ),
                      ),
                      Text(
                        group,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: TColors.cyan,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Text(
                    'name:',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: TColors.mutedText,
                    ),
                  ),
                  SizedBox(height: 4),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: TColors.border),
                    ),
                    child: TextField(
                      controller: _nameCtrl,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: TColors.foreground,
                      ),
                      decoration: InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      autocorrect: false,
                      enableSuggestions: false,
                    ),
                  ),
                  SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TermButton(
                        label: 'cancel',
                        onTap: () => Navigator.of(context).pop(),
                        color: TColors.comment,
                        bordered: true,
                      ),
                      SizedBox(width: 8),
                      _saving
                          ? SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: TColors.mutedText,
                              ),
                            )
                          : TermButton(
                              label: 'save',
                              onTap: _save,
                              color: TColors.green,
                              bordered: true,
                            ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);

    try {
      await ref.read(sampleServiceProvider).save(
        widget.projectId,
        widget.requestRelativePath,
        name,
        widget.response.bodyText,
        widget.response.statusCode ?? 0,
        widget.response.headers,
        widget.response.contentType,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('sample saved as $name'),
            backgroundColor: TColors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('failed to save: $e'),
            backgroundColor: TColors.red,
          ),
        );
        setState(() => _saving = false);
      }
    }
  }
}
