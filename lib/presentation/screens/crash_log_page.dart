import 'package:curel/domain/models/crash_log_model.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CrashLogPage extends ConsumerStatefulWidget {
  const CrashLogPage({super.key});

  @override
  ConsumerState<CrashLogPage> createState() => _CrashLogPageState();
}

class _CrashLogPageState extends ConsumerState<CrashLogPage> {
  List<CrashLog> _logs = [];
  bool _loading = true;
  int? _filterSeverity;
  int _expandedId = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final logs = await ref
        .read(crashLogServiceProvider)
        .getAll(severity: _filterSeverity);
    if (mounted) setState(() { _logs = logs; _loading = false; });
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
            _buildFilters(),
            Container(height: 1, color: TColors.border),
            Expanded(
              child: _loading
                  ? const Center(child: TerminalLoader())
                  : _buildList(),
            ),
            Container(height: 1, color: TColors.border),
            _buildFooter(),
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
          Text(
            'crash log',
            style: TextStyle(
              color: TColors.foreground,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(width: 8),
          Text(
            '${_logs.length}',
            style: TextStyle(
              color: TColors.mutedText,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      color: TColors.surface,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          _filterChip(null, 'all'),
          SizedBox(width: 4),
          _filterChip(Severity.critical, 'critical'),
          SizedBox(width: 4),
          _filterChip(Severity.error, 'error'),
          SizedBox(width: 4),
          _filterChip(Severity.warning, 'warn'),
          SizedBox(width: 4),
          _filterChip(Severity.info, 'info'),
        ],
      ),
    );
  }

  Widget _filterChip(int? severity, String label) {
    final active = _filterSeverity == severity;
    final color = severity != null ? _severityColor(severity) : TColors.foreground;
    return GestureDetector(
      onTap: () {
        setState(() {
          _filterSeverity = severity;
          _loading = true;
        });
        _load();
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: active ? color : TColors.border),
          color: active ? color.withValues(alpha: 0.1) : Colors.transparent,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? color : TColors.mutedText,
            fontFamily: 'monospace',
            fontSize: 9,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_logs.isEmpty) {
      return Center(
        child: Text(
          'no logs',
          style: TextStyle(
            color: TColors.mutedText.withValues(alpha: 0.5),
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _logs.length,
      itemBuilder: (_, i) => _buildLogRow(_logs[i]),
    );
  }

  Widget _buildLogRow(CrashLog log) {
    final expanded = _expandedId == log.id;
    final color = _severityColor(log.severity);
    final time = '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}';
    final date = '${log.timestamp.month.toString().padLeft(2, '0')}-${log.timestamp.day.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expandedId = expanded ? -1 : log.id),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    _severityLabel(log.severity),
                    style: TextStyle(
                      color: color,
                      fontFamily: 'monospace',
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(width: 4),
                Text(
                  '$date $time',
                  style: TextStyle(
                    color: TColors.mutedText,
                    fontFamily: 'monospace',
                    fontSize: 9,
                  ),
                ),
                SizedBox(width: 6),
                Text(
                  log.context,
                  style: TextStyle(
                    color: TColors.cyan,
                    fontFamily: 'monospace',
                    fontSize: 9,
                  ),
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    log.message,
                    style: TextStyle(
                      color: TColors.foreground,
                      fontFamily: 'monospace',
                      fontSize: 9,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 12,
                  color: TColors.mutedText,
                ),
              ],
            ),
          ),
        ),
        if (expanded) _buildExpanded(log),
        Container(height: 1, color: TColors.border.withValues(alpha: 0.3)),
      ],
    );
  }

  Widget _buildExpanded(CrashLog log) {
    return Container(
      padding: EdgeInsets.fromLTRB(60, 4, 12, 8),
      color: TColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            log.message,
            style: TextStyle(
              color: TColors.foreground,
              fontFamily: 'monospace',
              fontSize: 10,
            ),
          ),
          if (log.stackTrace != null && log.stackTrace!.isNotEmpty) ...[
            SizedBox(height: 4),
            Container(
              padding: EdgeInsets.all(6),
              color: TColors.background,
              child: Text(
                log.stackTrace!,
                style: TextStyle(
                  color: TColors.mutedText,
                  fontFamily: 'monospace',
                  fontSize: 9,
                  height: 1.4,
                ),
                maxLines: 20,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      color: TColors.surface,
      padding: EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        children: [
          TermButton(icon: Icons.refresh, label: 'refresh', onTap: () {
            setState(() => _loading = true);
            _load();
          }),
          Spacer(),
          TermButton(
            icon: Icons.delete_forever,
            label: 'clear',
            onTap: () async {
              await ref.read(crashLogServiceProvider).clear();
              _load();
            },
          ),
        ],
      ),
    );
  }

  Color _severityColor(int severity) {
    return switch (severity) {
      Severity.critical => TColors.red,
      Severity.error => TColors.orange,
      Severity.warning => TColors.yellow,
      Severity.info => TColors.cyan,
      _ => TColors.foreground,
    };
  }

  String _severityLabel(int severity) {
    return switch (severity) {
      Severity.critical => 'CRIT',
      Severity.error => 'ERRO',
      Severity.warning => 'WARN',
      Severity.info => 'INFO',
      _ => '????',
    };
  }
}
