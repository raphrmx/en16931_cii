import 'dart:io';

import 'package:en16931_cii/en16931_cii.dart';
import 'package:test/test.dart';

void main() {
  test('a document written to the standard is read whole', () {
    final directory = Directory('examples_from_cef');
    if (!directory.existsSync()) {
      markTestSkipped('Run tool/fetch_examples.dart');
      return;
    }
    for (final file in directory.listSync().whereType<File>()) {
      final read = readCiiReporting(file.readAsStringSync());
      expect(
        read.isComplete,
        isTrue,
        reason: '${file.uri.pathSegments.last}: ${read.skipped}',
      );
    }
  });

  test('an ordinary line is not mistaken for a line under a line', () {
    // Counting the element outright would count every line of every invoice,
    // which is the easy way to get this wrong.
    final read = readCiiReporting(_invoice(lines: 3));
    expect(read.invoice.lines, hasLength(3));
    expect(read.isComplete, isTrue);
  });

  test('a line under a line is counted and not read', () {
    final read = readCiiReporting(_invoice(children: 2));
    expect(read.invoice.lines, hasLength(1));
    expect(read.isComplete, isFalse);

    final nested = read.skipped.single;
    expect(nested.name, 'ram:IncludedSupplyChainTradeLineItem');
    expect(nested.count, 2);
    expect(nested.purpose, contains('line under a line'));
  });

  test('gives the same invoice readCii gives', () {
    final xml = _invoice();
    expect(readCiiReporting(xml).invoice.number, readCii(xml).number);
  });

  test('refuses what readCii refuses', () {
    expect(
      () => readCiiReporting('not xml at all'),
      throwsA(isA<CiiFormatException>()),
    );
  });

  test('every element looked for says what it is', () {
    expect(ciiElementsBeyondTheModel, isNotEmpty);
    for (final entry in ciiElementsBeyondTheModel.entries) {
      expect(entry.key, startsWith('ram:'));
      expect(entry.value, isNotEmpty);
    }
  });
}

/// An invoice of [lines] lines, the first carrying [children] under it.
String _invoice({int lines = 1, int children = 0}) {
  const line = 'ram:IncludedSupplyChainTradeLineItem';
  final body = StringBuffer();
  for (var index = 0; index < lines; index++) {
    body.writeln('      <$line>');
    body.writeln('        <ram:AssociatedDocumentLineDocument>');
    body.writeln('          <ram:LineID>${index + 1}</ram:LineID>');
    body.writeln('        </ram:AssociatedDocumentLineDocument>');
    if (index == 0) {
      for (var child = 0; child < children; child++) {
        body.writeln('        <$line>');
        body.writeln('          <ram:AssociatedDocumentLineDocument>');
        body.writeln('            <ram:LineID>1.${child + 1}</ram:LineID>');
        body.writeln('          </ram:AssociatedDocumentLineDocument>');
        body.writeln('        </$line>');
      }
    }
    body.writeln('      </$line>');
  }

  final document = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<rsm:CrossIndustryInvoice')
    ..writeln('    xmlns:rsm="$_rsm"')
    ..writeln('    xmlns:ram="$_ram"')
    ..writeln('    xmlns:udt="$_udt">')
    ..writeln('  <rsm:ExchangedDocument>')
    ..writeln('    <ram:ID>2026-0042</ram:ID>')
    ..writeln('    <ram:TypeCode>380</ram:TypeCode>')
    ..writeln('    <ram:IssueDateTime>')
    ..writeln('      $_issued')
    ..writeln('    </ram:IssueDateTime>')
    ..writeln('  </rsm:ExchangedDocument>')
    ..writeln('  <rsm:SupplyChainTradeTransaction>')
    ..write(body)
    ..writeln('  </rsm:SupplyChainTradeTransaction>')
    ..writeln('</rsm:CrossIndustryInvoice>');
  return document.toString();
}

const String _rsm =
    'urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100';
const String _ram =
    'urn:un:unece:uncefact:data:standard:'
    'ReusableAggregateBusinessInformationEntity:100';
const String _udt =
    'urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100';

/// The issue date, written the way CII writes one.
const String _issued =
    '<udt:DateTimeString format="102">20260914</udt:DateTimeString>';
