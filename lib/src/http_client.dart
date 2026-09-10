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
      Sightpane.maybeClient?.recordSpan(
        op: 'http.client',
        name: '${request.method} ${request.url}',
        durationMs: sw.elapsedMilliseconds.toDouble(),
        status: r.statusCode.toString(),
        tags: {'status': r.statusCode, 'method': request.method, 'url': request.url.toString()},
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
      Sightpane.maybeClient?.recordSpan(
        op: 'http.client',
        name: '${request.method} ${request.url}',
        durationMs: sw.elapsedMilliseconds.toDouble(),
        status: 'error',
        tags: {'error': e.toString(), 'method': request.method, 'url': request.url.toString()},
      );
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}
