import 'package:curel/domain/models/crash_log_model.dart';
import 'package:curel/presentation/screens/feedback_page.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:flutter/material.dart';

class CrashLogDetailPage extends StatelessWidget {
  final CrashLog log;

  const CrashLogDetailPage({required this.log, super.key});

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
      Severity.critical => 'CRITICAL',
      Severity.error => 'ERROR',
      Severity.warning => 'WARNING',
      Severity.info => 'INFO',
      _ => 'UNKNOWN',
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(log.severity);
    final date =
        '${log.timestamp.year}-${log.timestamp.month.toString().padLeft(2, '0')}-${log.timestamp.day.toString().padLeft(2, '0')}';
    final time =
        '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: TColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Container(height: 1, color: TColors.border),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabelRow('severity', _severityLabel(log.severity), color),
                    SizedBox(height: 8),
                    _buildLabelRow('timestamp', '$date $time', TColors.foreground),
                    SizedBox(height: 8),
                    _buildLabelRow('context', log.context, TColors.cyan),
                    SizedBox(height: 12),
                    Text(
                      'message',
                      style: TextStyle(
                        color: TColors.mutedText,
                        fontFamily: 'monospace',
                        fontSize: 10,
                      ),
                    ),
                    SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(8),
                      color: TColors.surface,
                      child: SelectableText(
                        log.message,
                        style: TextStyle(
                          color: TColors.foreground,
                          fontFamily: 'monospace',
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ),
                    if (log.stackTrace != null && log.stackTrace!.isNotEmpty) ...[
                      SizedBox(height: 12),
                      Text(
                        'stack trace',
                        style: TextStyle(
                          color: TColors.mutedText,
                          fontFamily: 'monospace',
                          fontSize: 10,
                        ),
                      ),
                      SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(8),
                        color: TColors.surface,
                        child: SelectableText(
                          log.stackTrace!,
                          style: TextStyle(
                            color: TColors.mutedText,
                            fontFamily: 'monospace',
                            fontSize: 9,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(height: 1, color: TColors.border),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
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
            'crash detail',
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

  Widget _buildLabelRow(String label, String value, Color valueColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: TextStyle(
              color: TColors.mutedText,
              fontFamily: 'monospace',
              fontSize: 10,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      color: TColors.surface,
      padding: EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        children: [
          TermButton(
            icon: Icons.bug_report,
            label: 'send as bug',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FeedbackPage(
                    initialTitle: '[crash] ${log.context}',
                    initialMessage: 'severity: ${_severityLabel(log.severity)}\n'
                        'context: ${log.context}\n'
                        'message: ${log.message}${log.stackTrace != null ? '\n\nstack trace:\n${log.stackTrace}' : ''}',
                  ),
                ),
              );
            },
            accent: true,
          ),
        ],
      ),
    );
  }
}
