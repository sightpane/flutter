import 'dart:js_interop';
import 'package:web/web.dart' as web;

void bindPageHide(void Function() onHide) {
  try {
    web.window.addEventListener(
      'visibilitychange',
      ((web.Event _) {
        if (web.document.visibilityState == 'hidden') {
          onHide();
        }
      }).toJS,
    );
    web.window.addEventListener(
      'pagehide',
      ((web.Event _) {
        onHide();
      }).toJS,
    );
  } catch (_) {}
}

