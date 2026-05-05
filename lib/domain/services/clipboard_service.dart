import 'package:flutter/services.dart';

abstract class ClipboardService {
  Future<String?> paste();
}

class FlutterClipboardService implements ClipboardService {
  @override
  Future<String?> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }
}
