import 'package:en16931/en16931.dart';
import 'package:en16931_cii/en16931_cii.dart';
import 'package:test/test.dart';

/// The invoice the README shows, kept here so the README cannot go stale
/// without a test going red.
Invoice _fromReadme() => Invoice.fromLines(
  number: '2026-0042',
  issueDate: DateTime(2026, 9, 13),
  dueDate: DateTime(2026, 10, 13),
  seller: const Seller(
    name: 'COMAPPS SRL',
    vatIdentifier: 'BE0123456789',
    electronicAddress: Identifier(
      '0123456749',
      scheme: Scheme.belgianEnterprise,
    ),
    address: Address(city: 'Bruxelles', postalCode: '1000', country: 'BE'),
  ),
  buyer: const Buyer(
    name: 'Client SA',
    electronicAddress: Identifier(
      '0987654394',
      scheme: Scheme.belgianEnterprise,
    ),
    address: Address(city: 'Namur', postalCode: '5000', country: 'BE'),
  ),
  lines: [
    InvoiceLine.of(
      id: '1',
      item: const Item(name: 'Consulting'),
      quantity: 8,
      unitPrice: 150.00,
      vatRate: 21,
      unit: UnitCode.hour,
    ),
  ],
);

void main() {
  test('the invoice in the README passes validation', () {
    expect(validate(_fromReadme()), isEmpty);
  });

  test('it writes out and reads back', () {
    final xml = writeCii(_fromReadme());
    final received = readCii(xml);
    expect(received.number, '2026-0042');
    expect(validate(received), isEmpty);
    expect(writeCii(received), xml);
  });
}
