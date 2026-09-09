// Uploads the source maps of a release so the backend can turn a minified
// stack trace back into Dart source (no Flutter, plain Dart).
//
//   flutter build web --source-maps
//   dart run tool/upload_sourcemap.dart \
//     --endpoint http://localhost:8790 --token "$SIGHTPANE_TOKEN" \
//     --project 1 --release 1.0.0 \
//     build/web/main.dart.js.map
//
// The release has to be the same string the app reports in
// SightpaneOptions.release, because that is what the server matches an error
// against. Run it as part of the deploy, before the build goes out: an error
// that arrives before its map is stored unsymbolicated and stays that way.
//
// The token is a user token (owner of the project), not the project API key.
// A source map is a build output; the key ships inside the app and may only
// write envelopes.
import 'dart:io';

import 'package:http/http.dart' as http;

const _usage = '''
usage: dart run tool/upload_sourcemap.dart [options] <file.map> [file.map ...]

  --endpoint  backend root, e.g. http://localhost:8790   (SIGHTPANE_ENDPOINT)
  --token     a user token for an owner of the project   (SIGHTPANE_TOKEN)
  --project   project id                                 (SIGHTPANE_PROJECT)
  --release   the release these maps belong to           (SIGHTPANE_RELEASE)
''';

Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final opts = <String, String>{
    'endpoint': env['SIGHTPANE_ENDPOINT'] ?? '',
    'token': env['SIGHTPANE_TOKEN'] ?? '',
    'project': env['SIGHTPANE_PROJECT'] ?? '',
    'release': env['SIGHTPANE_RELEASE'] ?? '',
  };
  final files = <String>[];
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('--')) {
      files.add(a);
      continue;
    }
    final name = a.substring(2);
    if (!opts.containsKey(name)) {
      _fail('unknown option $a');
    }
    if (i + 1 >= args.length) {
      _fail('$a needs a value');
    }
    opts[name] = args[++i];
  }
  for (final e in opts.entries) {
    if (e.value.isEmpty) _fail('--${e.key} is required');
  }
  if (files.isEmpty) _fail('give at least one .map file');

  final base = opts['endpoint']!.replaceAll(RegExp(r'/+$'), '');
  final url = Uri.parse(
    '$base/api/v1/projects/${opts['project']}'
    '/releases/${Uri.encodeComponent(opts['release']!)}/sourcemaps',
  );

  var failed = 0;
  for (final path in files) {
    final f = File(path);
    if (!f.existsSync()) {
      stderr.writeln('$path: no such file');
      failed++;
      continue;
    }
    final req = http.MultipartRequest('POST', url)
      ..headers['Authorization'] = 'Bearer ${opts['token']}'
      ..files.add(await http.MultipartFile.fromPath('file', path));
    final res = await http.Response.fromStream(await req.send());
    if (res.statusCode == 201) {
      final n = f.lengthSync();
      final size = n < 1024 ? '$n B' : '${(n / 1024).round()} KB';
      stdout.writeln('uploaded ${f.uri.pathSegments.last} ($size)');
    } else {
      stderr.writeln('$path: ${res.statusCode} ${res.body}');
      failed++;
    }
  }
  if (failed > 0) {
    // A failed upload must fail the deploy step it runs in, or the first error
    // of the release is the thing that tells you about it.
    exit(1);
  }
}

Never _fail(String message) {
  stderr.writeln('$message\n\n$_usage');
  exit(2);
}
