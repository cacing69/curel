import 'package:curel/domain/adapters/collection_adapter.dart';
import 'package:curel/domain/models/project_model.dart';
import 'package:curel/domain/services/workspace_service.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:flutter/material.dart';

class ImportPreviewDialog extends StatefulWidget {
  final PreviewResult preview;
  final List<Project> projects;

  const ImportPreviewDialog({
    required this.preview,
    this.projects = const [],
    super.key,
  });

  @override
  State<ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<ImportPreviewDialog> {
  String? _selectedProjectId;

  @override
  Widget build(BuildContext context) {
    final c = widget.preview.collection;
    return Dialog(
      backgroundColor: TColors.background,
      insetPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Container(
        constraints: BoxConstraints(maxWidth: 360, maxHeight: 480),
        decoration: BoxDecoration(border: Border.all(color: TColors.border)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context),
            Container(height: 1, color: TColors.border),
            Flexible(child: _body(c)),
            Container(height: 1, color: TColors.border),
            _footer(context),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      color: TColors.surface,
      child: Row(
        children: [
          Icon(Icons.upload_file, size: 14, color: TColors.green),
          SizedBox(width: 6),
          Text(
            'import collection',
            style: TextStyle(
              color: TColors.green,
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          Spacer(),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Icon(Icons.close, size: 14, color: TColors.comment),
          ),
        ],
      ),
    );
  }

  Widget _body(ImportedCollection c) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _targetSelector(c.name),
          SizedBox(height: 8),
          Container(height: 1, color: TColors.border),
          SizedBox(height: 8),
          _row('source', widget.preview.adapterName),
          _row('name', c.name),
          if (c.description != null && c.description!.isNotEmpty)
            _row('desc', c.description!),
          if (c.requests.isNotEmpty) ...[
            SizedBox(height: 8),
            _sectionHeader('requests', c.requests.length, TColors.cyan),
            ...c.requests.take(15).map((r) => _item(
              r.path.replaceAll('.curl', ''),
            )),
            if (c.requests.length > 15)
              _more(c.requests.length - 15),
          ],
          if (c.environments.isNotEmpty) ...[
            SizedBox(height: 8),
            _sectionHeader('environments', c.environments.length, TColors.purple),
            ...c.environments.map((e) => _item(
              '${e.name} (${e.variables.length})',
            )),
          ],
        ],
      ),
    );
  }

  Widget _targetSelector(String collectionName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'import to',
          style: TextStyle(
            color: TColors.green,
            fontFamily: 'monospace',
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 4),
        _targetOption(null, 'new project: $collectionName'),
        if (widget.projects.isNotEmpty)
          ...widget.projects.map((p) => _targetOption(p.id, p.name)),
      ],
    );
  }

  Widget _targetOption(String? id, String label) {
    final selected = _selectedProjectId == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedProjectId = id),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        margin: EdgeInsets.only(bottom: 2),
        color: selected ? TColors.surface : Colors.transparent,
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 12,
              color: selected ? TColors.green : TColors.comment,
            ),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? TColors.green : TColors.foreground,
                  fontFamily: 'monospace',
                  fontSize: 10,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                color: TColors.comment,
                fontFamily: 'monospace',
                fontSize: 10,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: TColors.foreground,
                fontFamily: 'monospace',
                fontSize: 10,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label, int count, Color color) {
    return Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontFamily: 'monospace',
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
              color: color.withValues(alpha: 0.7),
              fontFamily: 'monospace',
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(String text) {
    return Padding(
      padding: EdgeInsets.only(left: 8, bottom: 1),
      child: Text(
        '▸ $text',
        style: TextStyle(
          color: TColors.foreground,
          fontFamily: 'monospace',
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _more(int count) {
    return Padding(
      padding: EdgeInsets.only(left: 8),
      child: Text(
        '... +$count more',
        style: TextStyle(
          color: TColors.comment,
          fontFamily: 'monospace',
          fontSize: 10,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      color: TColors.surface,
      child: Row(
        children: [
          Spacer(),
          _btn(context, 'cancel', TColors.comment, () => Navigator.of(context).pop()),
          SizedBox(width: 6),
          _btn(context, 'import', TColors.green, () => Navigator.of(context).pop(_selectedProjectId ?? '')),
        ],
      ),
    );
  }

  Widget _btn(BuildContext context, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 26,
        padding: EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(border: Border.all(color: color)),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontFamily: 'monospace',
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
