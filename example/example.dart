// ignore_for_file: avoid_print

import 'package:en16931/en16931.dart';
import 'package:en16931_cii/en16931_cii.dart';

/// Builds an invoice, checks it, and writes it out as UBL.
void main() {
  final invoice = Invoice.fromLines(
    number: '2026-0042',
    issueDate: DateTime(2026, 9, 13),
    dueDate: DateTime(2026, 10, 13),
    seller: const Seller(
      name: 'COMAPPS SRL',
      vatIdentifier: 'BE0123456789',
      electronicAddress: Identifier(
        '0123456789',
        scheme: Scheme.belgianEnterprise,
      ),
      address: Address(city: 'Bruxelles', postalCode: '1000', country: 'BE'),
    ),
    buyer: const Buyer(
      name: 'Client SA',
      electronicAddress: Identifier(
        '0987654321',
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

  final violations = validate(invoice);
  if (violations.isNotEmpty) {
    for (final violation in violations) {
      print(violation);
    }
    return;
  }

  final xml = writeCii(invoice);
  print(xml);

  // What the other side does with it.
  receive(xml);
}

/// Reads a UBL document back and reports what its issuer got wrong.
void receive(String xml) {
  final invoice = readCii(xml);
  print('${invoice.number} from ${invoice.seller.name}');
  final violations = validate(invoice);
  if (violations.isEmpty) {
    print('  nothing to object to');
    return;
  }
  for (final violation in violations) {
    print('  $violation');
  }
}
