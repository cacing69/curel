import 'package:curel/data/app_config.dart';
import 'package:curel/data/services/github_oauth_service.dart';
import 'package:curel/domain/models/crash_log_model.dart';
import 'package:curel/domain/models/git_provider_model.dart';
import 'package:curel/domain/providers/services.dart';
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ps = await ref.read(gitProviderServiceProvider).getAll();
    if (mounted) {
      setState(() {
        _providers = ps;
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

    GitHubOAuthService oauth;
    try {
      oauth = GitHubOAuthService(clientId: curelGitHubClientId);
    } catch (e) {
      crashLog.log(Severity.error, 'oauth', 'setup failed: $e');
      if (outerCtx.mounted) showTerminalToast(outerCtx, 'oauth setup failed: $e');
      return;
    }

    DeviceFlowResponse deviceFlow;
    try {
      deviceFlow = await oauth.startDeviceFlow();
    } catch (e) {
      crashLog.log(Severity.error, 'oauth', 'start device flow failed: $e');
      if (outerCtx.mounted) showTerminalToast(outerCtx, 'failed to start device flow: $e');
      return;
    }

    if (!outerCtx.mounted) return;

    final oauthResult = await showDialog<OAuthTokenResponse>(
      context: outerCtx,
      barrierDismissible: false,
      builder: (ctx) => _OAuthDeviceDialog(deviceFlow: deviceFlow, oauth: oauth),
    );

    if (oauthResult == null) {
      // user cancelled dialog — no need to log
      return;
    }

    if (oauthResult.isError) {
      crashLog.log(Severity.warning, 'oauth',
          '${oauthResult.error}: ${oauthResult.errorDescription}');
      if (outerCtx.mounted) showTerminalToast(outerCtx, oauthResult.errorDescription ?? 'oauth failed');
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
      final provider = await ref.read(gitProviderServiceProvider).create(
        name: providerName,
        type: 'github',
        baseUrl: baseUrl.isNotEmpty ? baseUrl : null,
        token: token,
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

  Future<void> _deleteProvider(GitProviderModel provider) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TColors.background,
        title: Text(
          'delete provider?',
          style: TextStyle(
            color: TColors.foreground,
            fontFamily: 'monospace',
            fontSize: 14,
          ),
        ),
        content: Text(
          'are you sure you want to delete ${provider.name}?',
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
              'delete',
              style: TextStyle(color: TColors.red, fontFamily: 'monospace'),
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

  Widget _buildTile(GitProviderModel provider) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.cloud_circle, size: 16, color: TColors.cyan),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider.name,
                  style: TextStyle(
                    color: TColors.foreground,
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'type: ${provider.type}${provider.baseUrl != null && provider.baseUrl!.isNotEmpty ? ' | url: ${provider.baseUrl}' : ''}',
                  style: TextStyle(
                    color: TColors.mutedText,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.edit, size: 16, color: TColors.mutedText),
            onPressed: () => _showProviderDialog(provider: provider),
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(),
          ),
          SizedBox(width: 16),
          IconButton(
            icon: Icon(Icons.delete, size: 16, color: TColors.red),
            onPressed: () => _deleteProvider(provider),
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(),
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
  final DeviceFlowResponse deviceFlow;
  final GitHubOAuthService oauth;

  const _OAuthDeviceDialog({
    required this.deviceFlow,
    required this.oauth,
  });

  @override
  State<_OAuthDeviceDialog> createState() => _OAuthDeviceDialogState();
}

class _OAuthDeviceDialogState extends State<_OAuthDeviceDialog> {
  String _status = 'waiting for authorization...';
  bool _isPolling = true;
  bool _isDone = false;

  @override
  void initState() {
    super.initState();
    _poll();
  }

  Future<void> _poll() async {
    final result = await widget.oauth.pollForToken(
      widget.deviceFlow.deviceCode,
      interval: widget.deviceFlow.interval,
      expiresIn: widget.deviceFlow.expiresIn,
    );

    if (!mounted) return;

    if (result.isError) {
      setState(() {
        _isPolling = false;
        _status = result.errorDescription ?? 'authorization failed';
      });
      return;
    }

    setState(() {
      _isPolling = false;
      _isDone = true;
    });

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
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
              widget.deviceFlow.userCode,
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
            widget.deviceFlow.verificationUri,
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
              final uri = Uri.tryParse(widget.deviceFlow.verificationUri);
              if (uri != null) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            accent: true,
          ),
          SizedBox(height: 16),
          if (_isPolling)
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
              )
            else
              Text(
                _status,
                style: TextStyle(
                  color: TColors.red,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
          ],
        ),
      actions: [
        if (!_isDone)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'cancel',
              style: TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
              ),
            ),
          ),
      ],
    );
  }
}
