import 'dart:io';

import 'package:en16931/en16931.dart';
import 'package:en16931_cii/en16931_cii.dart';
import 'package:test/test.dart';

/// The example invoices the standard is published with.
///
/// They are EUPL 1.2 and are not part of this repository. Run
/// `dart run tool/fetch_examples.dart` to pull them in, and these tests wake
/// up. Reading our own output back proves the writer and the reader agree
/// with each other; reading these proves they agree with everyone else.
const String _directory = 'examples_from_cef';

/// What is really wrong with the few examples that are.
///
/// XRechnung-O writes its VAT exemption reason code in lower case, where the
/// VATEX list is upper case and the rule compares them as written.
const Map<String, Set<String>> _knownBad = {
  'XRechnung-O.xml': {'BR-CL-22'},
};

void main() {
  final directory = Directory(_directory);
  if (!directory.existsSync()) {
    test('the published examples', () {}, skip: 'Run tool/fetch_examples.dart');
    return;
  }

  final files = directory.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('there are examples to read', () {
    expect(files, isNotEmpty);
  });

  for (final file in files) {
    final name = file.uri.pathSegments.last;

    group(name, () {
      late Invoice invoice;

      setUp(() {
        invoice = readCii(file.readAsStringSync());
      });

      test('is read', () {
        expect(invoice.number, isNotEmpty);
        expect(invoice.lines, isNotEmpty);
        expect(invoice.seller.name, isNotEmpty);
        expect(invoice.buyer.name, isNotEmpty);
      });

      test('breaks no rule it should not', () {
        // These are the documents the standard publishes as examples of
        // itself, so a violation usually means this library reads or checks
        // something wrong. The exceptions are documents that really are
        // wrong, and each is named with what is wrong with it.
        final broken =
            validate(invoice).map((violation) => violation.rule.id).toSet();
        expect(broken.difference(_knownBad[name] ?? const {}), isEmpty);
      });

      test('survives being written and read again', () {
        final once = writeCii(invoice);
        final twice = writeCii(readCii(once));
        expect(twice, once);
      });
    });
  }
}
