import 'lifecycle_web.dart' if (dart.library.io) 'lifecycle_io.dart' as impl;

/// Binds browser pagehide/visibilitychange events to trigger flush on web.
void bindPageHide(void Function() onHide) => impl.bindPageHide(onHide);
