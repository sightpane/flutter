import 'package:http/http.dart' as http;

import 'client.dart';
import 'models.dart';

/// A `package:http` client that records every request as an `http` breadcrumb.
class SightpaneHttpClient extends http.BaseClient {
  SightpaneHttpClient([http.Client? inner]) : _inner = inner ?? http.Client();
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final sw = Stopwatch()..start();
    try {
      final r = await _inner.send(request);
      Sightpane.addBreadcrumb(
        SightpaneBreadcrumb(
          category: 'http',
          message: '${request.method} ${request.url}',
          level: r.statusCode >= 400
              ? SightpaneLevel.warning
              : SightpaneLevel.info,
          data: {'status': r.statusCode, 'ms': sw.elapsedMilliseconds},
        ),
      );
      return r;
    } catch (e) {
      Sightpane.addBreadcrumb(
        SightpaneBreadcrumb(
          category: 'http',
          message: '${request.method} ${request.url}',
          level: SightpaneLevel.error,
          data: {'error': e.toString(), 'ms': sw.elapsedMilliseconds},
        ),
      );
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}
