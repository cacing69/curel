import 'dart:async';

import 'package:curel/data/app_config.dart';
import 'package:curel/data/services/github_oauth_service.dart';
import 'package:curel/domain/models/crash_log_model.dart';
import 'package:curel/domain/models/git_provider_model.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:curel/domain/services/crash_log_service.dart';
import 'package:curel/domain/services/git_client.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

class GitProvidersPage extends ConsumerStatefulWidget {
  GitProvidersPage({super.key});

  @override
  ConsumerState<GitProvidersPage> createState() => _GitProvidersPageState();
}

class _GitProvidersPageState extends ConsumerState<GitProvidersPage> {
  List<GitProviderModel> _providers = [];
  Map<String, bool> _tokenExists = {};
  Map<String, DateTime?> _tokenExpiresAt = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = ref.read(gitProviderServiceProvider);
    final ps = await svc.getAll();
    final tokenMap = <String, bool>{};
    final expiryMap = <String, DateTime?>{};
    for (final p in ps) {
      tokenMap[p.id] = await svc.hasToken(p.id);
      expiryMap[p.id] = await svc.getTokenExpiresAt(p.id);
    }
    if (mounted) {
      setState(() {
        _providers = ps;
        _tokenExists = tokenMap;
        _tokenExpiresAt = expiryMap;
        _loading = false;
      });
    }
  }

  Future<void> _showProviderDialog({GitProviderModel? provider}) async {
    final isEdit = provider != null;
    final nameCtrl = TextEditingController(text: provider?.name ?? '');
    final typeCtrl = TextEditingController(text: provider?.type ?? 'github');
    final baseUrlCtrl = TextEditingController(text: provider?.baseUrl ?? '');
    final tokenCtrl = TextEditingController();

    await showDialog<bool>(
      context: context,
      builder: (ctx) {
        bool validating = false;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: TColors.background,
              title: Text(
                isEdit ? 'edit provider' : 'add provider',
                style: TextStyle(
                  color: TColors.foreground,
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildField('name', 'my github', nameCtrl),
                    SizedBox(height: 12),
                    Text(
                      'type',
                      style: TextStyle(
                        color: TColors.cyan,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(height: 6),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      color: TColors.background,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: typeCtrl.text,
                          dropdownColor: TColors.surface,
                          isExpanded: true,
                          style: TextStyle(
                            color: TColors.foreground,
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                          items: [
                            DropdownMenuItem(value: 'github', child: Text('github')),
                            DropdownMenuItem(value: 'gitlab', child: Text('gitlab')),
                            DropdownMenuItem(value: 'gitea', child: Text('gitea')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setStateDialog(() => typeCtrl.text = v);
                            }
                          },
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    _buildField(
                      'base url (optional)',
                      typeCtrl.text == 'github'
                          ? 'https://github.company.com'
                          : typeCtrl.text == 'gitlab'
                              ? 'https://gitlab.company.com'
                              : 'https://gitea.company.com',
                      baseUrlCtrl,
                    ),
                    SizedBox(height: 12),
                    _buildField(
                      isEdit ? 'token (leave empty to keep)' : 'token (pat)',
                      typeCtrl.text == 'github'
                          ? 'ghp_xxx...'
                          : typeCtrl.text == 'gitlab'
                              ? 'glpat-xxx...'
                              : 'gtp_xxx...',
                      tokenCtrl,
                      obscure: true,
                    ),
                    if (!isEdit && typeCtrl.text == 'github') ...[
                      SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: Container(height: 1, color: TColors.mutedText.withValues(alpha: 0.3))),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              'or',
                              style: TextStyle(
                                color: TColors.mutedText,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                          ),
                          Expanded(child: Container(height: 1, color: TColors.mutedText.withValues(alpha: 0.3))),
                        ],
                      ),
                      SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: TermButton(
                          icon: Icons.login,
                          label: 'login with github',
                          onTap: () => _startOAuthFlow(
                            ctx,
                            nameCtrl.text.trim(),
                            baseUrlCtrl.text.trim(),
                          ),
                          accent: true,
                          fullWidth: true,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: validating ? null : () => Navigator.of(ctx).pop(false),
                  child: Text(
                    'cancel',
                    style: TextStyle(
                      color: TColors.mutedText,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: validating
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          final type = typeCtrl.text;
                          var baseUrl = baseUrlCtrl.text.trim();
                          final token = tokenCtrl.text.trim();

                          if (name.isEmpty) return;
                          if (!isEdit && token.isEmpty) return;

                          setStateDialog(() => validating = true);

                          try {
                            final tokenToValidate = isEdit ? (token.isNotEmpty ? token : null) : token;
                            if (tokenToValidate != null) {
                              final client = GitClient.create(type, baseUrl: baseUrl);
                              final username = await client.validateToken(tokenToValidate, baseUrl: baseUrl);
                              if (username == null) {
                                if (mounted) showTerminalToast(ctx, 'invalid token — check your credentials');
                                setStateDialog(() => validating = false);
                                return;
                              }
                            }

                            if (isEdit) {
                              await ref.read(gitProviderServiceProvider).update(
                                    provider.copyWith(name: name, type: type, baseUrl: baseUrl),
                                    newToken: token.isNotEmpty ? token : null,
                                  );
                            } else {
                              await ref.read(gitProviderServiceProvider).create(
                                    name: name,
                                    type: type,
                                    baseUrl: baseUrl,
                                    token: token,
                                  );
                            }
                            if (mounted) Navigator.of(ctx).pop(true);
                          } catch (e) {
                            if (mounted) showTerminalToast(ctx, 'error: $e');
                            setStateDialog(() => validating = false);
                          }
                        },
                  child: validating
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: TColors.green))
                      : Text(
                          'save',
                          style: TextStyle(
                            color: TColors.green,
                            fontFamily: 'monospace',
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );

    await _load();
  }

  Future<void> _startOAuthFlow(
    BuildContext outerCtx,
    String name,
    String baseUrl,
  ) async {
    final crashLog = ref.read(crashLogServiceProvider);
    final oauth = GitHubOAuthService(clientId: curelGitHubClientId);

    final oauthResult = await showDialog<OAuthTokenResponse>(
      context: outerCtx,
      barrierDismissible: false,
      builder: (ctx) => _OAuthDeviceDialog(
        oauth: oauth,
        crashLog: crashLog,
      ),
    );

    if (oauthResult == null) {
      return;
    }

    final token = oauthResult.accessToken;
    if (token == null || token.isEmpty) {
      crashLog.log(Severity.error, 'oauth', 'no token received after successful polling');
      if (outerCtx.mounted) showTerminalToast(outerCtx, 'oauth failed: no token received');
      return;
    }

    String providerName = name;
    if (providerName.isEmpty) {
      try {
        final client = GitClient.create('github', baseUrl: baseUrl.isNotEmpty ? baseUrl : null);
        final username = await client.validateToken(token);
        providerName = 'github (${username ?? 'unknown'})';
      } catch (_) {
        providerName = 'github';
      }
    }

    try {
      final expiresAt = oauthResult.expiresIn != null
          ? DateTime.now().add(Duration(seconds: oauthResult.expiresIn!))
          : null;
      final provider = await ref.read(gitProviderServiceProvider).create(
        name: providerName,
        type: 'github',
        baseUrl: baseUrl.isNotEmpty ? baseUrl : null,
        token: token,
        refreshToken: oauthResult.refreshToken,
        expiresAt: expiresAt,
      );

      if (outerCtx.mounted) {
        Navigator.of(outerCtx).pop(true);
        showTerminalToast(outerCtx, 'github provider "${provider.name}" added');
      }
    } catch (e) {
      crashLog.log(Severity.error, 'oauth', 'save provider failed: $e');
      if (outerCtx.mounted) showTerminalToast(outerCtx, 'error saving provider: $e');
    }
  }

  Widget _buildField(
    String label,
    String hint,
    TextEditingController controller, {
    bool obscure = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: TColors.cyan,
            fontFamily: 'monospace',
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 6),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: TColors.surface,
          child: TextField(
            controller: controller,
            obscureText: obscure,
            cursorColor: TColors.green,
            style: TextStyle(
              color: TColors.foreground,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
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

  Future<void> _deleteProvider(GitProviderModel provider,
      {String? reason}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TColors.background,
        title: Text(
          reason != null ? 'logout' : 'delete provider',
          style: TextStyle(
            color: reason != null ? TColors.orange : TColors.red,
            fontFamily: 'monospace',
            fontSize: 14,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              reason ?? 'are you sure you want to delete ${provider.name}?',
              style: TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
            if (reason != null) ...[
              SizedBox(height: 8),
              Text(
                'provider: ${provider.name}',
                style: TextStyle(
                  color: TColors.foreground,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'cancel',
              style: TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              reason != null ? 'logout' : 'delete',
              style: TextStyle(
                color: reason != null ? TColors.orange : TColors.red,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );

    if (result == true) {
      await ref.read(gitProviderServiceProvider).delete(provider.id);
      await _load();
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
            Expanded(
              child: _loading
                  ? const Center(child: TerminalLoader())
                  : _providers.isEmpty
                  ? _buildEmpty()
                  : ListView.separated(
                      itemCount: _providers.length,
                      separatorBuilder: (_, __) =>
                          Container(height: 1, color: TColors.border),
                      itemBuilder: (_, i) => _buildTile(_providers[i]),
                    ),
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
            child: Icon(
              Icons.arrow_back,
              size: 18,
              color: TColors.mutedText,
            ),
          ),
          SizedBox(width: 8),
          Text(
            'git providers',
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

  Widget _buildEmpty() {
    return Center(
      child: Text(
        'no git providers configured.\nadd one to enable remote sync.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: TColors.mutedText,
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _icon(IconData icon, Color color, VoidCallback onTap, {String? tooltip}) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }

  Widget _buildTile(GitProviderModel provider) {
    final hasToken = _tokenExists[provider.id] ?? false;
    final expiresAt = _tokenExpiresAt[provider.id];
    final isExpired = expiresAt != null && DateTime.now().isAfter(expiresAt);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: TColors.surface,
              border: Border.all(color: TColors.border, width: 0.5),
            ),
            child: Center(
              child: Text(
                provider.type[0].toUpperCase(),
                style: TextStyle(
                  color: hasToken
                      ? (isExpired ? TColors.red : TColors.green)
                      : TColors.mutedText,
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hasToken
                            ? (isExpired ? TColors.red : TColors.green)
                            : TColors.mutedText,
                      ),
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        provider.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: TColors.foreground,
                          fontFamily: 'monospace',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  '${provider.type}${provider.baseUrl != null && provider.baseUrl!.isNotEmpty ? ' | ${provider.baseUrl}' : ''}',
                  style: TextStyle(
                    color: TColors.mutedText,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _icon(Icons.edit, TColors.mutedText,
                  () => _showProviderDialog(provider: provider)),
              SizedBox(width: 2),
              _icon(Icons.logout, TColors.orange,
                  () => _deleteProvider(provider,
                      reason: 'log out from ${provider.name}? this will revoke the token.'),
                  tooltip: 'logout & revoke token'),
              SizedBox(width: 2),
              _icon(Icons.delete, TColors.red,
                  () => _deleteProvider(provider),
                  tooltip: 'remove provider'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      color: TColors.surface,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          TermButton(
            icon: Icons.add,
            label: 'add provider',
            onTap: () => _showProviderDialog(),
            accent: true,
          ),
        ],
      ),
    );
  }
}

class _OAuthDeviceDialog extends StatefulWidget {
  final GitHubOAuthService oauth;
  final CrashLogService crashLog;

  const _OAuthDeviceDialog({
    required this.oauth,
    required this.crashLog,
  });

  @override
  State<_OAuthDeviceDialog> createState() => _OAuthDeviceDialogState();
}

class _OAuthDeviceDialogState extends State<_OAuthDeviceDialog> {
  static const int _maxRetries = 3;

  DeviceFlowResponse? _deviceFlow;
  String _status = 'starting...';
  bool _loading = true;
  bool _isPolling = false;
  String? _errorDetail;
  int _secondsRemaining = 0;
  int _retryCount = 0;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _startFlow();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _startFlow() async {
    setState(() {
      _loading = true;
      _isPolling = false;
      _status = 'starting...';
      _errorDetail = null;
    });

    try {
      final flow = await widget.oauth.startDeviceFlow();
      if (!mounted) return;

      setState(() {
        _deviceFlow = flow;
        _loading = false;
        _isPolling = true;
        _status = 'waiting for authorization...';
        _secondsRemaining = flow.expiresIn;
      });

      _startCountdown();
      _poll(flow);
    } catch (e) {
      widget.crashLog.log(Severity.error, 'oauth', 'start device flow failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _isPolling = false;
        _errorDetail = '$e';
        _status = 'failed to start';
      });
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(Duration(seconds: 1), (_) {
      if (!mounted) {
        _countdownTimer?.cancel();
        return;
      }
      setState(() {
        if (_secondsRemaining > 0) _secondsRemaining--;
      });
    });
  }

  Future<void> _poll(DeviceFlowResponse flow) async {
    try {
      final result = await widget.oauth.pollForToken(
        flow.deviceCode,
        interval: flow.interval,
        expiresIn: flow.expiresIn,
      );

      if (!mounted) return;

      if (result.isError) {
        if (result.error == 'timeout') {
          _handleTimeout();
          return;
        }
        setState(() {
          _isPolling = false;
          _errorDetail = result.errorDescription;
          _status = result.error ?? 'authorization failed';
        });
        return;
      }

      _countdownTimer?.cancel();
      setState(() {
        _isPolling = false;
        _status = 'authorization successful!';
      });
      await Future.delayed(Duration(milliseconds: 800));
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      widget.crashLog.log(Severity.warning, 'oauth', 'poll error: $e');
      if (!mounted) return;
      setState(() {
        _isPolling = false;
        _errorDetail = '$e';
        _status = 'connection error';
      });
    }
  }

  void _handleTimeout() {
    if (_retryCount >= _maxRetries) {
      widget.crashLog.log(Severity.warning, 'oauth',
          'device flow timed out after $_maxRetries retries');
      setState(() {
        _isPolling = false;
        _status = 'timed out';
        _errorDetail =
            'no authorization after ${_maxRetries + 1} attempts. try again later.';
      });
      return;
    }

    _retryCount++;
    widget.crashLog.log(Severity.warning, 'oauth',
        'device flow timed out, retry $_retryCount/$_maxRetries');
    _countdownTimer?.cancel();
    _restartFlow();
  }

  Future<void> _restartFlow() async {
    setState(() {
      _loading = true;
      _status = 'restarting (${_retryCount}/$_maxRetries)...';
    });

    try {
      final flow = await widget.oauth.startDeviceFlow();
      if (!mounted) return;

      setState(() {
        _deviceFlow = flow;
        _loading = false;
        _isPolling = true;
        _status = 'new code generated — enter it in your browser';
        _secondsRemaining = flow.expiresIn;
      });

      _startCountdown();
      _poll(flow);
    } catch (e) {
      widget.crashLog.log(Severity.error, 'oauth', 'restart device flow failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _isPolling = false;
        _errorDetail = '$e';
        _status = 'restart failed';
      });
    }
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<bool> _onPop() async {
    if (!_isPolling) return true;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TColors.background,
        title: Text(
          'cancel authorization?',
          style: TextStyle(
            color: TColors.foreground,
            fontFamily: 'monospace',
            fontSize: 14,
          ),
        ),
        content: Text(
          'authorization is in progress. are you sure?',
          style: TextStyle(
            color: TColors.mutedText,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'no, wait',
              style: TextStyle(
                color: TColors.cyan,
                fontFamily: 'monospace',
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'yes, cancel',
              style: TextStyle(
                color: TColors.red,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );

    return confirm ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isPolling,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          final shouldPop = await _onPop();
          if (shouldPop && mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: AlertDialog(
        backgroundColor: TColors.background,
        title: Text(
          'github authorization',
          style: TextStyle(
            color: TColors.foreground,
            fontFamily: 'monospace',
            fontSize: 14,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (_loading)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: TColors.green,
                    ),
                    SizedBox(height: 12),
                    Text(
                      _status,
                      style: TextStyle(
                        color: TColors.mutedText,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              )
            else if (_deviceFlow != null) ...[
              Text(
                'enter the code below in your browser:',
                style: TextStyle(
                  color: TColors.mutedText,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: TColors.surface,
                  border: Border.all(color: TColors.border),
                ),
                child: SelectableText(
                  _deviceFlow!.userCode,
                  style: TextStyle(
                    color: TColors.green,
                    fontFamily: 'monospace',
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                  ),
                ),
              ),
              SizedBox(height: 12),
              SelectableText(
                _deviceFlow!.verificationUri,
                style: TextStyle(
                  color: TColors.cyan,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
              SizedBox(height: 8),
              TermButton(
                icon: Icons.open_in_browser,
                label: 'open link',
                onTap: () async {
                  final uri = Uri.tryParse(_deviceFlow!.verificationUri);
                  if (uri != null) {
                    await launchUrl(
                        uri, mode: LaunchMode.externalApplication);
                  }
                },
                accent: true,
              ),
              SizedBox(height: 12),
              if (_isPolling) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: TColors.green,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      _status,
                      style: TextStyle(
                        color: TColors.mutedText,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  'code expires in ${_formatTime(_secondsRemaining)}',
                  style: TextStyle(
                    color: _secondsRemaining < 60
                        ? TColors.red
                        : TColors.mutedText,
                    fontFamily: 'monospace',
                    fontSize: 10,
                  ),
                ),
              ] else ...[
                Text(
                  _status,
                  style: TextStyle(
                    color: _errorDetail == null ? TColors.green : TColors.red,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
                if (_errorDetail != null) ...[
                  SizedBox(height: 4),
                  Text(
                    _errorDetail!,
                    style: TextStyle(
                      color: TColors.mutedText,
                      fontFamily: 'monospace',
                      fontSize: 10,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ] else ...[
              Text(
                _status,
                style: TextStyle(
                  color: TColors.red,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
              if (_errorDetail != null) ...[
                SizedBox(height: 4),
                Text(
                  _errorDetail!,
                  style: TextStyle(
                    color: TColors.mutedText,
                    fontFamily: 'monospace',
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ],
        ),
        actions: [
          if (_isPolling)
            TextButton(
              onPressed: () {
                _countdownTimer?.cancel();
                Navigator.of(context).pop();
              },
              child: Text(
                'cancel',
                style: TextStyle(
                  color: TColors.mutedText,
                  fontFamily: 'monospace',
                ),
              ),
            )
          else ...[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'close',
                style: TextStyle(
                  color: TColors.mutedText,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            if (_errorDetail != null)
              TextButton(
                onPressed: _retryCount >= _maxRetries
                    ? () => Navigator.of(context).pop()
                    : _restartFlow,
                child: Text(
                  _retryCount >= _maxRetries ? 'done' : 'retry',
                  style: TextStyle(
                    color: _retryCount >= _maxRetries
                        ? TColors.mutedText
                        : TColors.cyan,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
