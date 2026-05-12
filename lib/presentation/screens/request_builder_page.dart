import 'dart:convert';

import 'package:curel/data/models/curl_response.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:curel/domain/services/curl_parser_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

// ── Models ──────────────────────────────────────────────────────

enum HttpMethod { get, post, put, delete, head, options, patch }

enum BodyType { none, json, formData, urlEncoded, raw }

enum BuilderTab { params, headers, body, auth, cookies }

class KeyValueEntry {
  String key;
  String value;
  bool enabled;

  KeyValueEntry({this.key = '', this.value = '', this.enabled = true});
}

class FormDataEntry {
  String name;
  String value;
  bool isFile;
  Uint8List? fileBytes;
  String? fileName;

  FormDataEntry({
    this.name = '',
    this.value = '',
    this.isFile = false,
    this.fileBytes,
    this.fileName,
  });
}

// ── Page ────────────────────────────────────────────────────────

class RequestBuilderPage extends ConsumerStatefulWidget {
  final String? initialCurl;
  final String? projectId;

  RequestBuilderPage({
    this.initialCurl,
    this.projectId,
    super.key,
  });

  @override
  ConsumerState<RequestBuilderPage> createState() => _RequestBuilderPageState();
}

class _RequestBuilderPageState extends ConsumerState<RequestBuilderPage> {
  late HttpMethod _method;
  late String _url;
  late List<KeyValueEntry> _headers;
  late List<KeyValueEntry> _queryParams;
  late BodyType _bodyType;
  late String _bodyContent;
  late List<FormDataEntry> _formDataEntries;
  late String _authUser;
  late String _authPassword;
  late String _bearerToken;
  late List<KeyValueEntry> _cookies;

  var _selectedTab = BuilderTab.headers;
  var _isLoading = false;

  // Persistent controllers
  late final _urlController = TextEditingController();
  late final _bodyController = TextEditingController();
  late final _authUserController = TextEditingController();
  late final _authPasswordController = TextEditingController();
  late final _bearerTokenController = TextEditingController();
  List<String> _envKeys = [];
  List<({String key, String lower})> _envKeyIndex = [];
  final _autocompleteValues = <TextEditingController, TextEditingValue>{};

  @override
  void initState() {
    super.initState();
    _parseAndInit(widget.initialCurl);
    _refreshEnvKeys();
  }

  Future<void> _refreshEnvKeys() async {
    final keys = <String>{};
    final global = await ref.read(envServiceProvider).getActive(null);
    if (global != null) {
      keys.addAll(global.variables.map((v) => v.key));
    }
    if (widget.projectId != null) {
      final project = await ref.read(envServiceProvider).getActive(widget.projectId);
      if (project != null) {
        keys.addAll(project.variables.map((v) => v.key));
      }
    }
    if (!mounted) return;
    final sorted = keys.toList()..sort();
    setState(() {
      _envKeys = sorted;
      _envKeyIndex = sorted
          .map((k) => (key: k, lower: k.toLowerCase()))
          .toList(growable: false);
    });
  }

  RenderEditable? _findRenderEditable(RenderObject root) {
    RenderEditable? result;
    void visitor(RenderObject child) {
      if (result != null) return;
      if (child is RenderEditable) {
        result = child;
        return;
      }
      child.visitChildren(visitor);
    }

    if (root is RenderEditable) return root;
    root.visitChildren(visitor);
    return result;
  }

  Offset _caretBottomInField({
    required GlobalKey fieldKey,
    required int caretOffset,
  }) {
    final fieldContext = fieldKey.currentContext;
    if (fieldContext == null) return Offset.zero;
    final fieldBox = fieldContext.findRenderObject() as RenderBox?;
    if (fieldBox == null) return Offset.zero;
    final root = fieldContext.findRenderObject();
    if (root == null) return Offset.zero;
    final renderEditable = _findRenderEditable(root);
    if (renderEditable == null) return Offset.zero;
    final caretRect = renderEditable.getLocalRectForCaret(
      TextPosition(offset: caretOffset),
    );
    final caretGlobal = renderEditable.localToGlobal(
      Offset(caretRect.left, caretRect.bottom),
    );
    return fieldBox.globalToLocal(caretGlobal);
  }

  ({int replaceStart, int replaceEnd, String query, bool hasClosing})?
  _envQueryAtCaret(TextEditingValue value) {
    final caret = value.selection.baseOffset;
    if (caret < 0) return null;
    final text = value.text;
    if (caret > text.length) return null;
    final before = text.substring(0, caret);
    final start = before.lastIndexOf('<<');
    if (start < 0) return null;
    if (before.indexOf('>>', start) != -1) return null;
    final query = before.substring(start + 2);
    if (query.isNotEmpty &&
        !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(query)) {
      return null;
    }
    final hasClosing = text.substring(caret).startsWith('>>');
    return (
      replaceStart: start + 2,
      replaceEnd: caret,
      query: query,
      hasClosing: hasClosing,
    );
  }

  Widget _envAutocompleteTextField({
    required TextEditingController controller,
    required TextStyle style,
    required InputDecoration decoration,
    ValueChanged<String>? onChanged,
    int? maxLines,
    bool obscureText = false,
  }) {
    if (_envKeys.isEmpty || obscureText) {
      return TextField(
        controller: controller,
        maxLines: maxLines,
        obscureText: obscureText,
        style: style,
        decoration: decoration,
        onChanged: onChanged,
      );
    }

    final fieldKey = GlobalObjectKey(controller);
    return RawAutocomplete<String>(
      textEditingController: controller,
      optionsBuilder: (value) {
        _autocompleteValues[controller] = value;
        final q = _envQueryAtCaret(value);
        if (q == null) return Iterable<String>.empty();
        final query = q.query.toLowerCase();
        return _envKeyIndex
            .where((e) => query.isEmpty || e.lower.startsWith(query))
            .map((e) => e.key)
            .take(12);
      },
      onSelected: (option) {
        final value = _autocompleteValues[controller] ?? controller.value;
        final q = _envQueryAtCaret(value);
        if (q == null) return;
        final insert = option + (q.hasClosing ? '' : '>>');
        final text = value.text.replaceRange(
          q.replaceStart,
          q.replaceEnd,
          insert,
        );
        final caret = q.replaceStart + insert.length;
        controller.value = value.copyWith(
          text: text,
          selection: TextSelection.collapsed(offset: caret),
          composing: TextRange.empty,
        );
      },
      fieldViewBuilder: (context, textController, focusNode, onSubmit) {
        return TextField(
          key: fieldKey,
          controller: textController,
          focusNode: focusNode,
          maxLines: maxLines,
          style: style,
          decoration: decoration,
          onChanged: onChanged,
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final list = options.toList();
        final box = fieldKey.currentContext?.findRenderObject() as RenderBox?;
        final size = box?.size ?? Size.zero;
        final menuMaxWidth = 260.0;
        final value = _autocompleteValues[controller] ?? controller.value;
        final caret = value.selection.baseOffset;
        final caretPoint = (caret >= 0 && caret <= value.text.length)
            ? _caretBottomInField(fieldKey: fieldKey, caretOffset: caret)
            : Offset.zero;
        final caretX = caretPoint.dx;
        final caretBottom = caretPoint.dy;
        final maxDx = size.width <= 0 ? 0.0 : (size.width - menuMaxWidth);
        final dx = maxDx <= 0 ? 0.0 : caretX.clamp(0.0, maxDx);
        final dy = size.height <= 0
            ? 0.0
            : (caretBottom - size.height).clamp(
                (-size.height + 4).clamp(-9999.0, 0.0),
                0.0,
              );
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: Colors.transparent,
            child: Transform.translate(
              offset: Offset(dx, dy),
              child: Container(
                margin: EdgeInsets.only(top: 4),
                constraints: BoxConstraints(
                  maxHeight: 180,
                  maxWidth: 260,
                ),
                decoration: BoxDecoration(
                  color: TColors.surface,
                  border: Border.all(color: TColors.border),
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final opt = list[index];
                    return InkWell(
                      onTap: () => onSelected(opt),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Text(
                          '<<$opt>>',
                          style: TextStyle(
                            color: TColors.foreground,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _parseAndInit(String? curlText) {
    _method = HttpMethod.get;
    _url = '';
    _headers = [KeyValueEntry()];
    _queryParams = [KeyValueEntry()];
    _bodyType = BodyType.none;
    _bodyContent = '';
    _formDataEntries = [FormDataEntry()];
    _authUser = '';
    _authPassword = '';
    _bearerToken = '';
    _cookies = [KeyValueEntry()];

    if (curlText == null || curlText.trim().isEmpty) return;

    try {
      final trimmed = curlText.trim();
      if (!trimmed.startsWith('curl')) return;

      final parsed = parseCurl(trimmed);
      final curl = parsed.curl;

      _method = HttpMethod.values.firstWhere(
        (m) => m.name.toUpperCase() == curl.method.toUpperCase(),
        orElse: () => HttpMethod.get,
      );

      _url = curl.uri.toString();

      // Parse query params from URL into the params tab
      if (curl.uri.hasQuery && curl.uri.queryParametersAll.isNotEmpty) {
        _url = curl.uri.replace(queryParameters: {}).toString();
        _queryParams = curl.uri.queryParametersAll.entries
            .expand(
              (e) => e.value.map((v) => KeyValueEntry(key: e.key, value: v)),
            )
            .toList();
      }

      if (curl.headers != null && curl.headers!.isNotEmpty) {
        _headers = curl.headers!.entries
            .map((e) => KeyValueEntry(key: e.key, value: e.value))
            .toList();
      }

      if (curl.form && curl.formData != null && curl.formData!.isNotEmpty) {
        _bodyType = BodyType.formData;
        _formDataEntries = curl.formData!
            .map(
              (fd) => FormDataEntry(
                name: fd.name,
                value: fd.value,
                isFile: fd.type.name == 'file',
              ),
            )
            .toList();
      } else if (curl.data != null && curl.data!.isNotEmpty) {
        _bodyContent = curl.data!;
        final ctHeader = _headers.where(
          (h) => h.key.toLowerCase() == 'content-type',
        );
        if (ctHeader.isNotEmpty) {
          final ct = ctHeader.first.value.toLowerCase();
          if (ct.contains('json')) {
            _bodyType = BodyType.json;
          } else if (ct.contains('x-www-form-urlencoded')) {
            _bodyType = BodyType.urlEncoded;
          } else {
            _bodyType = BodyType.raw;
          }
        } else if (_bodyContent.trimLeft().startsWith('{') ||
            _bodyContent.trimLeft().startsWith('[')) {
          _bodyType = BodyType.json;
        } else {
          _bodyType = BodyType.raw;
        }
      }

      if (curl.user != null && curl.user!.isNotEmpty) {
        final parts = curl.user!.split(':');
        _authUser = parts.first;
        _authPassword = parts.length > 1 ? parts.sublist(1).join(':') : '';
      }

      if (curl.cookie != null && curl.cookie!.isNotEmpty) {
        _cookies = curl.cookie!.split('; ').map((c) {
          final kv = c.split('=');
          return KeyValueEntry(
            key: kv.first,
            value: kv.length > 1 ? kv.sublist(1).join('=') : '',
          );
        }).toList();
      }
    } catch (_) {
      // keep defaults
    }

    // Sync controllers
    _urlController.text = _url;
    _bodyController.text = _bodyContent;
    _authUserController.text = _authUser;
    _authPasswordController.text = _authPassword;
    _bearerTokenController.text = _bearerToken;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _bodyController.dispose();
    _authUserController.dispose();
    _authPasswordController.dispose();
    _bearerTokenController.dispose();
    super.dispose();
  }

  bool get _hasBody =>
      _method == HttpMethod.post ||
      _method == HttpMethod.put ||
      _method == HttpMethod.delete ||
      _method == HttpMethod.patch;

  // ── Curl Generation ───────────────────────────────────────────

  String _buildCurlString() {
    final parts = <String>['curl'];

    final methodName = _method.name.toUpperCase();
    if (_method == HttpMethod.head) {
      parts.add('-I');
    } else if (_method != HttpMethod.get) {
      parts.add('-X $methodName');
    }

    // URL + query params
    var finalUrl = _url.trim();
    final activeParams = _queryParams.where(
      (p) => p.enabled && p.key.isNotEmpty,
    );
    if (activeParams.isNotEmpty) {
      final sep = finalUrl.contains('?') ? '&' : '?';
      final qs = activeParams
          .map(
            (p) =>
                '${Uri.encodeComponent(p.key)}=${Uri.encodeComponent(p.value)}',
          )
          .join('&');
      finalUrl = '$finalUrl$sep$qs';
    }
    if (finalUrl.isNotEmpty) parts.add("'$finalUrl'");

    // Headers
    for (final h in _headers) {
      if (h.enabled && h.key.isNotEmpty) {
        parts.add("-H '${h.key}: ${h.value}'");
      }
    }

    // Auth
    if (_authUser.isNotEmpty) {
      parts.add("-u '$_authUser:$_authPassword'");
    }
    if (_bearerToken.isNotEmpty) {
      parts.add("-H 'Authorization: Bearer $_bearerToken'");
    }

    // Cookies
    final activeCookies = _cookies.where((c) => c.enabled && c.key.isNotEmpty);
    if (activeCookies.isNotEmpty) {
      final cookieStr = activeCookies
          .map((c) => '${c.key}=${c.value}')
          .join('; ');
      parts.add("-b '$cookieStr'");
    }

    // Body
    if (_hasBody && _bodyType != BodyType.none) {
      switch (_bodyType) {
        case BodyType.json:
        case BodyType.urlEncoded:
        case BodyType.raw:
          if (_bodyContent.isNotEmpty) {
            parts.add("-d '$_bodyContent'");
          }
        case BodyType.formData:
          for (final entry in _formDataEntries) {
            if (entry.name.isEmpty) continue;
            if (entry.isFile) {
              parts.add("-F '${entry.name}=@${entry.fileName ?? entry.value}'");
            } else {
              parts.add("-F '${entry.name}=${entry.value}'");
            }
          }
        case BodyType.none:
          break;
      }
    }

    return parts.join(' \\\n  ');
  }

  // ── File Picker ───────────────────────────────────────────────

  Future<void> _pickFile(FormDataEntry entry) async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.single;
      setState(() {
        entry.value = file.name;
        entry.fileName = file.name;
        entry.fileBytes = file.bytes;
      });
    }
  }

  // ── Execution ─────────────────────────────────────────────────

  Future<void> _execute() async {
    if (_url.trim().isEmpty) {
      showTerminalToast(context, 'error: url is required');
      return;
    }

    final hasFiles =
        _bodyType == BodyType.formData &&
        _formDataEntries.any((e) => e.isFile && e.fileBytes != null);

    if (hasFiles) {
      await _executeDirect();
    } else {
      Navigator.of(context).pop(_buildCurlString());
    }
  }

  Future<void> _executeDirect() async {
    setState(() => _isLoading = true);
    final sw = Stopwatch()..start();
    try {
      final headers = <String, String>{};
      for (final h in _headers) {
        if (h.enabled && h.key.isNotEmpty) headers[h.key] = h.value;
      }
      if (_authUser.isNotEmpty) {
        headers['Authorization'] =
            'Basic ${base64Encode(utf8.encode('$_authUser:$_authPassword'))}';
      }
      if (_bearerToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $_bearerToken';
      }
      final activeCookies = _cookies.where(
        (c) => c.enabled && c.key.isNotEmpty,
      );
      if (activeCookies.isNotEmpty) {
        headers['Cookie'] = activeCookies
            .map((c) => '${c.key}=${c.value}')
            .join('; ');
      }

      final formData = FormData();
      for (final entry in _formDataEntries) {
        if (entry.name.isEmpty) continue;
        if (entry.isFile && entry.fileBytes != null) {
          formData.files.add(
            MapEntry(
              entry.name,
              MultipartFile.fromBytes(
                entry.fileBytes!,
                filename: entry.fileName,
              ),
            ),
          );
        } else {
          formData.fields.add(MapEntry(entry.name, entry.value));
        }
      }

      final response = await Dio().request<String>(
        _url.trim(),
        data: formData,
        options: Options(
          method: _method.name.toUpperCase(),
          headers: headers,
          responseType: ResponseType.plain,
          validateStatus: (s) => s != null && s < 600,
        ),
      );

      final elapsed = sw.elapsedMilliseconds;
      if (elapsed < 500) {
        await Future.delayed(Duration(milliseconds: 500 - elapsed));
      }

      final curlResponse = CurlResponse(
        statusCode: response.statusCode,
        statusMessage: response.statusMessage ?? '',
        headers: response.headers.map,
        body: response.data,
      );

      if (mounted) Navigator.of(context).pop(curlResponse);
    } catch (e) {
      final elapsed = sw.elapsedMilliseconds;
      if (elapsed < 500) {
        await Future.delayed(Duration(milliseconds: 500 - elapsed));
      }
      if (mounted) showTerminalToast(context, 'error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: TColors.background,
      body: SafeArea(child: isLandscape ? _buildLandscape() : _buildPortrait()),
    );
  }

  Widget _buildPortrait() {
    return Column(
      children: [
        _buildHeader(),
        Container(height: 1, color: TColors.border),
        _buildMethodUrlRow(),
        Container(height: 1, color: TColors.border),
        _buildTabBar(),
        Container(height: 1, color: TColors.border),
        Expanded(
          child: _isLoading
              ? Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: TColors.green,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'executing...',
                        style: TextStyle(
                          color: TColors.mutedText,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              : _buildTabContent(),
        ),
        Container(height: 1, color: TColors.border),
        _buildFooter(),
      ],
    );
  }

  Widget _buildLandscape() {
    return Column(
      children: [
        _buildHeader(),
        Container(height: 1, color: TColors.border),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: config
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    _buildMethodUrlRow(),
                    Container(height: 1, color: TColors.border),
                    _buildTabBar(),
                    Container(height: 1, color: TColors.border),
                    Expanded(
                      child: _isLoading
                          ? Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: TColors.green,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'executing...',
                                    style: TextStyle(
                                      color: TColors.mutedText,
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : _buildTabContent(),
                    ),
                  ],
                ),
              ),
              Container(width: 1, color: TColors.border),
              // Right: curl preview
              Expanded(flex: 2, child: _buildCurlPreview()),
            ],
          ),
        ),
        Container(height: 1, color: TColors.border),
        _buildFooter(),
      ],
    );
  }

  Widget _buildCurlPreview() {
    final curl = _buildCurlString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: TColors.surface,
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Text(
                'curl preview',
                style: TextStyle(
                  color: TColors.purple,
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Spacer(),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: curl));
                  showTerminalToast(context, 'curl copied to clipboard');
                },
                child: Icon(
                  Icons.copy,
                  size: 14,
                  color: TColors.mutedText,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(12),
            child: SelectableText(
              curl,
              style: TextStyle(
                color: TColors.text,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Header ────────────────────────────────────────────────────

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
            'builder',
            style: TextStyle(
              color: TColors.foreground,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
          Spacer(),
          GestureDetector(
            onTap: _isLoading ? null : _execute,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              color: TColors.green.withValues(alpha: 0.15),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow, size: 14, color: TColors.green),
                  SizedBox(width: 4),
                  Text(
                    'exec',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: TColors.green,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Method + URL ──────────────────────────────────────────────

  Widget _buildMethodUrlRow() {
    return Container(
      color: TColors.surface,
      padding: EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          _buildMethodDropdown(),
          SizedBox(width: 8),
          Expanded(
            child: _envAutocompleteTextField(
              controller: _urlController,
              style: TextStyle(
                color: TColors.text,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'https://api.example.com/endpoint',
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
              onChanged: (v) => _url = v,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodDropdown() {
    return GestureDetector(
      onTap: () => _showMethodPicker(),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: TColors.background,
          border: Border.all(color: TColors.border, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _method.name.toUpperCase(),
              style: TextStyle(
                color: _methodColor(_method),
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(width: 4),
            Icon(Icons.unfold_more, size: 12, color: TColors.mutedText),
          ],
        ),
      ),
    );
  }

  void _showMethodPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: TColors.background,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: HttpMethod.values.map((m) {
            return ListTile(
              dense: true,
              title: Text(
                m.name.toUpperCase(),
                style: TextStyle(
                  color: _methodColor(m),
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              trailing: m == _method
                  ? Icon(Icons.check, size: 16, color: TColors.green)
                  : null,
              onTap: () {
                setState(() => _method = m);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Color _methodColor(HttpMethod method) => switch (method) {
    HttpMethod.get => TColors.green,
    HttpMethod.post => TColors.yellow,
    HttpMethod.put => TColors.cyan,
    HttpMethod.delete => TColors.red,
    HttpMethod.head => TColors.purple,
    HttpMethod.options => TColors.orange,
    HttpMethod.patch => TColors.pink,
  };

  String _bodyTypeLabel(BodyType bt) => switch (bt) {
    BodyType.none => 'none',
    BodyType.json => 'JSON',
    BodyType.formData => 'form-data',
    BodyType.urlEncoded => 'x-www-form',
    BodyType.raw => 'raw',
  };

  // ── Tab Bar ───────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Container(
      color: TColors.surface,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: BuilderTab.values.map((tab) {
          final selected = _selectedTab == tab;
          if (tab == BuilderTab.body && !_hasBody) {
            return SizedBox.shrink();
          }
          return Padding(
            padding: EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => setState(() => _selectedTab = tab),
              child: Container(
                padding: EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: selected ? TColors.green : Colors.transparent,
                      width: 1,
                    ),
                  ),
                ),
                child: Text(
                  tab.name,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: selected ? TColors.foreground : TColors.mutedText,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTabContent() => switch (_selectedTab) {
    BuilderTab.params => _buildParamsTab(),
    BuilderTab.headers => _buildHeadersTab(),
    BuilderTab.body => _buildBodyTab(),
    BuilderTab.auth => _buildAuthTab(),
    BuilderTab.cookies => _buildCookiesTab(),
  };

  // ── Params Tab ────────────────────────────────────────────────

  Widget _buildParamsTab() {
    return _buildKeyValueList(
      entries: _queryParams,
      onAdd: () => setState(() => _queryParams.add(KeyValueEntry())),
      onRemove: (i) => setState(() => _queryParams.removeAt(i)),
      onKeyChanged: (i, v) => _queryParams[i].key = v,
      onValueChanged: (i, v) => _queryParams[i].value = v,
      onToggle: (i, v) {
        _queryParams[i].enabled = v;
        setState(() {});
      },
      hintKey: 'key',
      hintValue: 'value',
    );
  }

  // ── Headers Tab ───────────────────────────────────────────────

  Widget _buildHeadersTab() {
    return _buildKeyValueList(
      entries: _headers,
      onAdd: () => setState(() => _headers.add(KeyValueEntry())),
      onRemove: (i) => setState(() => _headers.removeAt(i)),
      onKeyChanged: (i, v) => _headers[i].key = v,
      onValueChanged: (i, v) => _headers[i].value = v,
      onToggle: (i, v) {
        _headers[i].enabled = v;
        setState(() {});
      },
      hintKey: 'header',
      hintValue: 'value',
    );
  }

  // ── Cookies Tab ───────────────────────────────────────────────

  Widget _buildCookiesTab() {
    return _buildKeyValueList(
      entries: _cookies,
      onAdd: () => setState(() => _cookies.add(KeyValueEntry())),
      onRemove: (i) => setState(() => _cookies.removeAt(i)),
      onKeyChanged: (i, v) => _cookies[i].key = v,
      onValueChanged: (i, v) => _cookies[i].value = v,
      onToggle: (i, v) {
        _cookies[i].enabled = v;
        setState(() {});
      },
      hintKey: 'name',
      hintValue: 'value',
    );
  }

  Widget _buildKeyValueList({
    required List<KeyValueEntry> entries,
    required VoidCallback onAdd,
    required void Function(int) onRemove,
    required void Function(int, String) onKeyChanged,
    required void Function(int, String) onValueChanged,
    required void Function(int, bool) onToggle,
    required String hintKey,
    required String hintValue,
  }) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: entries.length,
            itemBuilder: (_, i) {
              final entry = entries[i];
              return Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      child: Checkbox(
                        value: entry.enabled,
                        onChanged: (v) => onToggle(i, v ?? true),
                        activeColor: TColors.green,
                        checkColor: TColors.background,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: _field(
                        initialText: entry.key,
                        hint: hintKey,
                        onChanged: (v) => onKeyChanged(i, v),
                      ),
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      flex: 3,
                      child: _field(
                        initialText: entry.value,
                        hint: hintValue,
                        onChanged: (v) => onValueChanged(i, v),
                      ),
                    ),
                    SizedBox(width: 4),
                    GestureDetector(
                      onTap: entries.length > 1 ? () => onRemove(i) : null,
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: entries.length > 1
                              ? TColors.red
                              : TColors.mutedText.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [TermButton(icon: Icons.add, label: 'add', onTap: onAdd)],
          ),
        ),
      ],
    );
  }

  // ── Body Tab ──────────────────────────────────────────────────

  Widget _buildBodyTab() {
    return Column(
      children: [
        _buildBodyTypeSelector(),
        Container(height: 1, color: TColors.border),
        Expanded(child: _buildBodyContent()),
      ],
    );
  }

  Widget _buildBodyTypeSelector() {
    return Container(
      color: TColors.surface,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: BodyType.values.map((bt) {
            final selected = _bodyType == bt;
            return Padding(
              padding: EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _bodyType = bt),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? TColors.green.withValues(alpha: 0.15)
                        : Colors.transparent,
                    border: Border.all(
                      color: selected ? TColors.green : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    _bodyTypeLabel(bt),
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: selected ? TColors.green : TColors.mutedText,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildBodyContent() => switch (_bodyType) {
    BodyType.none => Center(
      child: Text(
        'no body',
        style: TextStyle(
          color: TColors.mutedText.withValues(alpha: 0.5),
          fontFamily: 'monospace',
          fontSize: 12,
        ),
      ),
    ),
    BodyType.json => _buildBodyEditor(hint: '{\n  "key": "value"\n}'),
    BodyType.raw => _buildBodyEditor(hint: 'raw body content...'),
    BodyType.urlEncoded => _buildUrlEncodedList(),
    BodyType.formData => _buildFormDataList(
      entries: _formDataEntries,
      isFormData: true,
    ),
  };

  Widget _buildBodyEditor({required String hint}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: _envAutocompleteTextField(
        controller: _bodyController,
        maxLines: null,
        style: TextStyle(
          color: TColors.text,
          fontFamily: 'monospace',
          fontSize: 12,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: TColors.mutedText.withValues(alpha: 0.5),
            fontFamily: 'monospace',
            fontSize: 12,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (v) => _bodyContent = v,
      ),
    );
  }

  Widget _buildUrlEncodedList() {
    // Parse body content into entries once, store in state
    final entries = <FormDataEntry>[];
    if (_bodyContent.isNotEmpty) {
      for (final pair in _bodyContent.split('&')) {
        if (pair.isEmpty) continue;
        final kv = pair.split('=');
        entries.add(
          FormDataEntry(
            name: Uri.decodeComponent(kv.first),
            value: kv.length > 1 ? Uri.decodeComponent(kv[1]) : '',
          ),
        );
      }
    }
    if (entries.isEmpty) entries.add(FormDataEntry());

    void rebuild(List<FormDataEntry> updated) {
      _bodyContent = updated
          .where((e) => e.name.isNotEmpty)
          .map(
            (e) =>
                '${Uri.encodeComponent(e.name)}=${Uri.encodeComponent(e.value)}',
          )
          .join('&');
      _bodyController.text = _bodyContent;
    }

    return _buildFormDataList(
      entries: entries,
      isFormData: false,
      onRebuild: rebuild,
    );
  }

  Widget _buildFormDataList({
    required List<FormDataEntry> entries,
    bool isFormData = false,
    void Function(List<FormDataEntry>)? onRebuild,
  }) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: entries.length,
            itemBuilder: (_, i) {
              final entry = entries[i];
              return Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _field(
                        initialText: entry.name,
                        hint: 'key',
                        onChanged: (v) {
                          entry.name = v;
                          onRebuild?.call(entries);
                        },
                      ),
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      flex: 3,
                      child: entry.isFile && isFormData
                          ? _field(
                              initialText: entry.fileName ?? entry.value,
                              hint: 'tap to browse...',
                              readOnly: true,
                              onTap: () => _pickFile(entry),
                            )
                          : _field(
                              initialText: entry.value,
                              hint: 'value',
                              onChanged: (v) {
                                entry.value = v;
                                onRebuild?.call(entries);
                              },
                            ),
                    ),
                    if (isFormData) ...[
                      SizedBox(width: 4),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            entry.isFile = !entry.isFile;
                            if (!entry.isFile) {
                              entry.fileBytes = null;
                              entry.fileName = null;
                            }
                          });
                        },
                        child: Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.insert_drive_file,
                            size: 16,
                            color: entry.isFile
                                ? TColors.orange
                                : TColors.mutedText.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ],
                    SizedBox(width: 4),
                    GestureDetector(
                      onTap: entries.length > 1
                          ? () => setState(() {
                              if (isFormData) {
                                _formDataEntries.removeAt(i);
                              } else {
                                entries.removeAt(i);
                                onRebuild?.call(entries);
                              }
                            })
                          : null,
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: entries.length > 1
                              ? TColors.red
                              : TColors.mutedText.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              TermButton(
                icon: Icons.add,
                label: 'add',
                onTap: () => setState(() {
                  if (isFormData) {
                    _formDataEntries.add(FormDataEntry());
                  } else {
                    entries.add(FormDataEntry());
                    onRebuild?.call(entries);
                  }
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Auth Tab ──────────────────────────────────────────────────

  Widget _buildAuthTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'basic auth',
            style: TextStyle(
              color: TColors.purple,
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          _envAutocompleteTextField(
            controller: _authUserController,
            style: _fieldStyle,
            decoration: _fieldDecoration('username'),
            onChanged: (v) => _authUser = v,
          ),
          SizedBox(height: 6),
          _envAutocompleteTextField(
            controller: _authPasswordController,
            obscureText: true,
            style: _fieldStyle,
            decoration: _fieldDecoration('password'),
            onChanged: (v) => _authPassword = v,
          ),
          SizedBox(height: 20),
          Text(
            'bearer token',
            style: TextStyle(
              color: TColors.purple,
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          _envAutocompleteTextField(
            controller: _bearerTokenController,
            style: _fieldStyle,
            decoration: _fieldDecoration('token'),
            onChanged: (v) => _bearerToken = v,
          ),
        ],
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Container(
      color: TColors.surface,
      padding: EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        children: [
          TermButton(
            icon: Icons.code,
            label: 'generate curl',
            onTap: () {
              Clipboard.setData(ClipboardData(text: _buildCurlString()));
              showTerminalToast(context, 'curl copied to clipboard');
            },
          ),
          Spacer(),
          TermButton(
            icon: Icons.play_arrow,
            label: 'execute',
            onTap: _isLoading ? null : _execute,
            accent: true,
          ),
        ],
      ),
    );
  }

  // ── Reusable field builder ────────────────────────────────────

  static final _fieldStyle = TextStyle(
    color: TColors.text,
    fontFamily: 'monospace',
    fontSize: 12,
  );

  static InputDecoration _fieldDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
      color: TColors.mutedText,
      fontFamily: 'monospace',
      fontSize: 12,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: TColors.border, width: 1),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: TColors.border, width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: TColors.green, width: 1),
    ),
    isDense: true,
    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
  );

  Widget _field({
    required String initialText,
    required String hint,
    ValueChanged<String>? onChanged,
    bool readOnly = false,
    GestureTapCallback? onTap,
  }) {
    return _FieldWrapper(
      initialText: initialText,
      hint: hint,
      onChanged: onChanged,
      readOnly: readOnly,
      onTap: onTap,
      envKeyIndex: _envKeyIndex,
      envQueryAtCaret: _envQueryAtCaret,
    );
  }
}

/// Wraps a TextField with its own controller lifecycle.
/// Created fresh when the parent row is rebuilt, which is fine
/// since list items are keyed by index and only rebuilt on add/remove.
class _FieldWrapper extends StatefulWidget {
  final String initialText;
  final String hint;
  final ValueChanged<String>? onChanged;
  final bool readOnly;
  final GestureTapCallback? onTap;
  final List<({String key, String lower})> envKeyIndex;
  final ({int replaceStart, int replaceEnd, String query, bool hasClosing})?
  Function(TextEditingValue value)
  envQueryAtCaret;

  _FieldWrapper({
    required this.initialText,
    required this.hint,
    this.onChanged,
    this.readOnly = false,
    this.onTap,
    required this.envKeyIndex,
    required this.envQueryAtCaret,
  });

  @override
  State<_FieldWrapper> createState() => _FieldWrapperState();
}

class _FieldWrapperState extends State<_FieldWrapper> {
  late final _controller = TextEditingController(text: widget.initialText);
  final _fieldKey = GlobalKey();
  TextEditingValue _lastAutocompleteValue = TextEditingValue();

  @override
  void didUpdateWidget(covariant _FieldWrapper old) {
    super.didUpdateWidget(old);
    if (widget.initialText != old.initialText &&
        widget.initialText != _controller.text) {
      _controller.text = widget.initialText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget buildField(TextEditingController controller, FocusNode? focusNode) {
      return TextField(
        key: _fieldKey,
        controller: controller,
        focusNode: focusNode,
        readOnly: widget.readOnly,
        onTap: widget.onTap,
        style: TextStyle(
          color: widget.readOnly ? TColors.mutedText : TColors.text,
          fontFamily: 'monospace',
          fontSize: 12,
        ),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: TextStyle(
            color: TColors.mutedText,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: TColors.border, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: TColors.border, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: TColors.green, width: 1),
          ),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
        ),
        onChanged: widget.onChanged,
      );
    }

    if (widget.readOnly || widget.envKeyIndex.isEmpty) {
      return buildField(_controller, null);
    }

    RenderEditable? findRenderEditable(RenderObject root) {
      RenderEditable? result;
      void visitor(RenderObject child) {
        if (result != null) return;
        if (child is RenderEditable) {
          result = child;
          return;
        }
        child.visitChildren(visitor);
      }

      if (root is RenderEditable) return root;
      root.visitChildren(visitor);
      return result;
    }

    Offset caretBottomInField({required int caretOffset}) {
      final fieldContext = _fieldKey.currentContext;
      if (fieldContext == null) return Offset.zero;
      final fieldBox = fieldContext.findRenderObject() as RenderBox?;
      if (fieldBox == null) return Offset.zero;
      final root = fieldContext.findRenderObject();
      if (root == null) return Offset.zero;
      final renderEditable = findRenderEditable(root);
      if (renderEditable == null) return Offset.zero;
      final caretRect = renderEditable.getLocalRectForCaret(
        TextPosition(offset: caretOffset),
      );
      final caretGlobal = renderEditable.localToGlobal(
        Offset(caretRect.left, caretRect.bottom),
      );
      return fieldBox.globalToLocal(caretGlobal);
    }

    return RawAutocomplete<String>(
      textEditingController: _controller,
      optionsBuilder: (value) {
        _lastAutocompleteValue = value;
        final q = widget.envQueryAtCaret(value);
        if (q == null) return Iterable<String>.empty();
        final query = q.query.toLowerCase();
        return widget.envKeyIndex
            .where((e) => query.isEmpty || e.lower.startsWith(query))
            .map((e) => e.key)
            .take(12);
      },
      onSelected: (option) {
        final value = _lastAutocompleteValue;
        final q = widget.envQueryAtCaret(value);
        if (q == null) return;
        final insert = option + (q.hasClosing ? '' : '>>');
        final text = value.text.replaceRange(
          q.replaceStart,
          q.replaceEnd,
          insert,
        );
        final caret = q.replaceStart + insert.length;
        _controller.value = value.copyWith(
          text: text,
          selection: TextSelection.collapsed(offset: caret),
          composing: TextRange.empty,
        );
      },
      fieldViewBuilder: (context, c, f, onSubmit) {
        return buildField(c, f);
      },
      optionsViewBuilder: (context, onSelected, options) {
        final list = options.toList();
        final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
        final size = box?.size ?? Size.zero;
        final menuMaxWidth = 240.0;
        final caret = _lastAutocompleteValue.selection.baseOffset;
        final caretPoint =
            (caret >= 0 && caret <= _lastAutocompleteValue.text.length)
            ? caretBottomInField(caretOffset: caret)
            : Offset.zero;
        final maxDx = size.width <= 0 ? 0.0 : (size.width - menuMaxWidth);
        final dx = maxDx <= 0 ? 0.0 : caretPoint.dx.clamp(0.0, maxDx);
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: Colors.transparent,
            child: Transform.translate(
              offset: Offset(dx, 0),
              child: Container(
                margin: EdgeInsets.only(top: 6),
                constraints: BoxConstraints(
                  maxHeight: 180,
                  maxWidth: 240,
                ),
                decoration: BoxDecoration(
                  color: TColors.surface,
                  border: Border.all(color: TColors.border),
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final opt = list[index];
                    return InkWell(
                      onTap: () => onSelected(opt),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Text(
                          '<<$opt>>',
                          style: TextStyle(
                            color: TColors.foreground,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
