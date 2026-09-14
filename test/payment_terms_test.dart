import 'package:en16931/en16931.dart';
import 'package:en16931_cii/en16931_cii.dart';
import 'package:test/test.dart';

void main() {
  test(
    'the payment terms (BT-20) keep the line break that closes a discount',
    () {
      // Germany reads a discount for early payment out of that text and needs
      // the break. Every other term is trimmed and reflowed; this one cannot be.
      const terms = 'Zahlbar netto.\n#SKONTO#TAGE=14#PROZENT=2.00#\n';
      final invoice = Invoice.fromLines(
        number: '1',
        issueDate: DateTime(2026, 9, 14),
        paymentTerms: terms,
        seller: const Seller(
          name: 'COMAPPS SRL',
          vatIdentifier: 'BE0123456789',
          address: Address(
            city: 'Bruxelles',
            postalCode: '1000',
            country: 'BE',
          ),
        ),
        buyer: const Buyer(
          name: 'Client SA',
          address: Address(city: 'Namur', postalCode: '5000', country: 'BE'),
        ),
        lines: [
          InvoiceLine.of(
            id: '1',
            item: const Item(name: 'Consulting'),
            quantity: 1,
            unitPrice: 100,
            vatRate: 21,
          ),
        ],
      );
      expect(readCii(writeCii(invoice)).paymentTerms, terms);
    },
  );
}
