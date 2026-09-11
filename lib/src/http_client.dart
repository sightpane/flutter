import 'dart:math' as math;
import 'package:http/http.dart' as http;

import 'client.dart';
import 'models.dart';

String _randomTraceHex(int byteLength) {
  final rnd = math.Random();
  final bytes = List<int>.generate(byteLength, (_) => rnd.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// A `package:http` client that records every request as an `http` breadcrumb
/// and injects W3C `traceparent` headers for distributed tracing.
class SightpaneHttpClient extends http.BaseClient {
  SightpaneHttpClient([
    http.Client? inner,
    this.injectTraceparent = true,
  ]) : _inner = inner ?? http.Client();

  final http.Client _inner;
  final bool injectTraceparent;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final sw = Stopwatch()..start();
    final currentTx = Sightpane.currentTransaction;
    final traceId = currentTx?.traceId ?? _randomTraceHex(16);
    final spanId = _randomTraceHex(8);
    final parentSpanId = currentTx?.spanId;

    if (injectTraceparent && !request.headers.containsKey('traceparent')) {
      request.headers['traceparent'] = '00-$traceId-$spanId-01';
    }

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
        traceId: traceId,
        spanId: spanId,
        parentSpanId: parentSpanId,
        tags: {
          'status': r.statusCode,
          'method': request.method,
          'url': request.url.toString(),
          'http.status_code': r.statusCode,
          'http.method': request.method,
          'http.url': request.url.toString(),
        },
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
        traceId: traceId,
        spanId: spanId,
        parentSpanId: parentSpanId,
        tags: {
          'error': e.toString(),
          'method': request.method,
          'url': request.url.toString(),
          'http.method': request.method,
          'http.url': request.url.toString(),
        },
      );
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}
