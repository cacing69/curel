import 'package:curel/domain/models/captured_request.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TrafficLogPage extends ConsumerStatefulWidget {
  const TrafficLogPage({super.key});

  @override
  ConsumerState<TrafficLogPage> createState() => _TrafficLogPageState();
}

class _TrafficLogPageState extends ConsumerState<TrafficLogPage> {
  final List<CapturedRequest> _requests = [];
  bool _capturing = false;
  bool _installingCa = false;
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final service = ref.read(trafficCaptureServiceProvider);
    final isCapturing = await service.isCapturing();
    if (mounted) setState(() => _capturing = isCapturing);

    service.requests.listen((batch) {
      if (mounted) {
        setState(() {
          _requests.insertAll(0, batch);
          if (_requests.length > 500) {
            _requests.removeRange(500, _requests.length);
          }
        });
      }
    });
  }

  Future<void> _toggleCapture() async {
    final service = ref.read(trafficCaptureServiceProvider);
    if (_capturing) {
      await service.stopCapture();
      setState(() => _capturing = false);
    } else {
      final started = await service.startCapture();
      if (started) {
        setState(() => _capturing = true);
      }
    }
  }

  Future<void> _installCa() async {
    if (_installingCa) return;
    _installingCa = true;
    final service = ref.read(trafficCaptureServiceProvider);
    final certReady = await service.isCertReady();
    if (!certReady) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('certificate not ready — start capture first',
                style: TextStyle(fontFamily: 'monospace')),
            backgroundColor: TColors.red,
          ),
        );
      }
      _installingCa = false;
      return;
    }
    final result = await service.installRootCaResult();
    if (mounted) {
      final msg = switch (result) {
        'installer' => 'certificate installer opened',
        String r when r.startsWith('downloaded:') =>
            'saved to Downloads/curel_root_ca.crt',
        _ => 'failed: $result',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: TextStyle(fontFamily: 'monospace')),
          backgroundColor: result == 'installer' || (result?.startsWith('downloaded') ?? false)
              ? TColors.green : TColors.red,
        ),
      );
    }
    _installingCa = false;
  }

  Future<void> _sendToCurl(CapturedRequest req) async {
    final curl = req.toCurl();
    await Clipboard.setData(ClipboardData(text: curl));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('curl copied to clipboard', style: TextStyle(fontFamily: 'monospace')),
          backgroundColor: TColors.green,
        ),
      );
    }
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
            Expanded(child: _buildBody()),
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
            'traffic log',
            style: TextStyle(
              color: TColors.foreground,
              fontSize: 12,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(width: 8),
          if (_capturing)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: TColors.green,
                shape: BoxShape.circle,
              ),
            ),
          Spacer(),
          Text(
            '${_requests.length}',
            style: TextStyle(
              color: TColors.mutedText,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          SizedBox(width: 12),
          if (!_capturing)
            TermButton(
              label: 'install CA',
              onTap: _installCa,
              color: TColors.yellow,
              bordered: true,
              icon: Icons.security,
            ),
          SizedBox(width: 6),
          TermButton(
            label: _capturing ? 'stop' : 'start',
            onTap: _toggleCapture,
            color: _capturing ? TColors.red : TColors.green,
            bordered: true,
            icon: _capturing ? Icons.stop : Icons.play_arrow,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!_capturing && _requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_find, size: 32, color: TColors.mutedText.withValues(alpha: 0.3)),
            SizedBox(height: 8),
            Text(
              'start capture to see HTTP traffic',
              style: TextStyle(
                color: TColors.mutedText.withValues(alpha: 0.5),
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _requests.length,
      separatorBuilder: (_, __) => Container(height: 1, color: TColors.border.withValues(alpha: 0.2)),
      itemBuilder: (_, i) => _buildRequestRow(_requests[i], i),
    );
  }

  Widget _buildRequestRow(CapturedRequest req, int index) {
    final isSelected = _selectedIndex == index;
    final methodColor = _methodColor(req.method);

    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = isSelected ? null : index),
      child: Container(
        color: isSelected ? TColors.surface : Colors.transparent,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: methodColor.withValues(alpha: 0.15),
                  ),
                  child: Text(
                    req.method,
                    style: TextStyle(
                      color: methodColor,
                      fontFamily: 'monospace',
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    req.url.length > 80 ? '${req.url.substring(0, 80)}…' : req.url,
                    style: TextStyle(
                      color: TColors.foreground,
                      fontFamily: 'monospace',
                      fontSize: 10,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _sendToCurl(req),
                  child: Icon(Icons.copy, size: 14, color: TColors.mutedText),
                ),
              ],
            ),
            if (isSelected) ...[
              SizedBox(height: 8),
              _detailRow('host', req.host),
              if (req.sourceIp.isNotEmpty) _detailRow('ip', req.sourceIp),
              if (req.headers.isNotEmpty)
                _detailBlock('headers', req.headers),
              if (req.body.isNotEmpty)
                ExpandedBody(text: req.body),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
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
                fontSize: 9,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
                fontSize: 9,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailBlock(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: TColors.comment,
              fontFamily: 'monospace',
              fontSize: 9,
            ),
          ),
          SizedBox(height: 2),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(6),
            color: TColors.background,
            child: Text(
              value,
              style: TextStyle(
                color: TColors.cyan,
                fontFamily: 'monospace',
                fontSize: 9,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _methodColor(String method) {
    return switch (method) {
      'GET' => TColors.green,
      'POST' => TColors.cyan,
      'PUT' => TColors.orange,
      'PATCH' => TColors.yellow,
      'DELETE' => TColors.red,
      _ => TColors.foreground,
    };
  }
}

class ExpandedBody extends StatefulWidget {
  final String text;
  const ExpandedBody({required this.text, super.key});

  @override
  State<ExpandedBody> createState() => _ExpandedBodyState();
}

class _ExpandedBodyState extends State<ExpandedBody> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final display = _expanded ? widget.text : widget.text.length > 100
        ? '${widget.text.substring(0, 100)}…' : widget.text;

    return Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'body',
                style: TextStyle(
                  color: TColors.comment,
                  fontFamily: 'monospace',
                  fontSize: 9,
                ),
              ),
              if (widget.text.length > 100) ...[
                SizedBox(width: 4),
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Icon(
                    _expanded ? Icons.unfold_less : Icons.unfold_more,
                    size: 12,
                    color: TColors.mutedText,
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: 2),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(6),
            color: TColors.background,
            child: Text(
              display,
              style: TextStyle(
                color: TColors.foreground,
                fontFamily: 'monospace',
                fontSize: 9,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
