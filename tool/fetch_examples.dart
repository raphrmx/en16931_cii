// Downloads the UBL example invoices the standard is published with.
//
// The examples come from https://github.com/ConnectingEurope/eInvoicing-EN16931
// under the EUPL 1.2. They are read by the test suite and never redistributed,
// so they land in a directory git ignores.
//
// Usage:
//   dart run tool/fetch_examples.dart
import 'dart:convert';
import 'dart:io';

const String _listing =
    'https://api.github.com/repos/ConnectingEurope/eInvoicing-EN16931/'
    'contents/cii/examples';

const String _directory = 'examples_from_cef';

/// Anything larger is one document with a huge attachment, which says nothing
/// more about reading an invoice than the others do.
const int _sizeLimit = 512 * 1024;

Future<void> main() async {
  final client = HttpClient();
  try {
    final entries = await _json(client, _listing);
    Directory(_directory).createSync(recursive: true);
    var taken = 0;
    var skipped = 0;
    for (final entry in entries) {
      final name = entry['name'] as String;
      final size = entry['size'] as int;
      if (!name.toLowerCase().endsWith('.xml')) continue;
      if (size > _sizeLimit) {
        stdout.writeln('skipped $name (${size ~/ 1024} KB)');
        skipped++;
        continue;
      }
      final url = entry['download_url'] as String;
      final target = File('$_directory/$name');
      target.writeAsStringSync(await _text(client, url));
      taken++;
    }
    stdout.writeln('$taken examples in $_directory, $skipped skipped');
  } finally {
    client.close();
  }
}

Future<List<Map<String, dynamic>>> _json(HttpClient client, String url) async {
  final body = await _text(client, url);
  return (jsonDecode(body) as List).cast<Map<String, dynamic>>();
}

Future<String> _text(HttpClient client, String url) async {
  final request = await client.getUrl(Uri.parse(url));
  request.headers.set('User-Agent', 'en16931_cii');
  final token = Platform.environment['GITHUB_TOKEN'];
  if (token != null && token.isNotEmpty) {
    request.headers.set('Authorization', 'Bearer $token');
  }
  final response = await request.close();
  if (response.statusCode != 200) {
    throw HttpException('${response.statusCode} for $url');
  }
  return await response.transform(utf8.decoder).join();
}
