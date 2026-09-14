import 'package:en16931/en16931.dart';
import 'package:en16931_cii/en16931_cii.dart';
import 'package:test/test.dart';

/// An invoice that can be paid into either of two accounts.
Invoice _twoAccounts() => Invoice.fromLines(
  number: '2026-0042',
  issueDate: DateTime(2026, 9, 14),
  seller: const Seller(
    name: 'COMAPPS SRL',
    vatIdentifier: 'BE0123456789',
    address: Address(city: 'Bruxelles', postalCode: '1000', country: 'BE'),
  ),
  buyer: const Buyer(
    name: 'Client SA',
    address: Address(city: 'Namur', postalCode: '5000', country: 'BE'),
  ),
  paymentInstructions: const PaymentInstructions(
    means: PaymentMeansCode.sepaCreditTransfer,
    remittanceInformation: '+++090/9337/55493+++',
    creditTransfers: [
      CreditTransferAccount('BE68539007547034', name: 'Compte courant'),
      CreditTransferAccount('NL03INGB0004489902', name: 'Compte second'),
    ],
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

void main() {
  group('several accounts (BG-17 repeated)', () {
    test('are written as one payment means each', () {
      // UBL carries one account to a payment means. Writing both into one
      // group is not what the schema allows, and not what the published
      // examples do.
      final xml = writeCii(_twoAccounts());
      expect(
        RegExp('<ram:SpecifiedTradeSettlementPaymentMeans>').allMatches(xml),
        hasLength(2),
      );
      expect(
        RegExp('<ram:PayeePartyCreditorFinancialAccount>').allMatches(xml),
        hasLength(2),
      );
      for (final block in RegExp(
        r'<ram:SpecifiedTradeSettlementPaymentMeans>[\s\S]*?</ram:SpecifiedTradeSettlementPaymentMeans>',
      ).allMatches(xml)) {
        expect(
          RegExp(
            '<ram:PayeePartyCreditorFinancialAccount>',
          ).allMatches(block.group(0)!),
          hasLength(1),
        );
      }
    });

    test('repeat the means code in every group', () {
      final xml = writeCii(_twoAccounts());
      expect(
        RegExp('<ram:TypeCode>58</ram:TypeCode>').allMatches(xml),
        hasLength(2),
      );
      // BT-83 sits on the settlement in CII, not inside a payment means, so
      // it is written once however many accounts the invoice offers.
      expect(RegExp('<ram:PaymentReference>').allMatches(xml), hasLength(1));
    });

    test('come back as one instruction carrying both', () {
      final invoice = readCii(writeCii(_twoAccounts()));
      final accounts = invoice.paymentInstructions!.creditTransfers;
      expect(accounts, hasLength(2));
      expect(accounts.first.identifier, 'BE68539007547034');
      expect(accounts.last.identifier, 'NL03INGB0004489902');
      expect(accounts.last.name, 'Compte second');
      expect(
        invoice.paymentInstructions!.remittanceInformation,
        '+++090/9337/55493+++',
      );
    });

    test('survive being written and read twice over', () {
      final once = writeCii(_twoAccounts());
      expect(writeCii(readCii(once)), once);
    });

    test('leave the invoice satisfying the standard', () {
      expect(validate(readCii(writeCii(_twoAccounts()))), isEmpty);
    });

    test('the card and the mandate are written once, not once per group', () {
      final invoice = Invoice.fromLines(
        number: '1',
        issueDate: DateTime(2026, 9, 14),
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
        paymentInstructions: const PaymentInstructions(
          means: PaymentMeansCode.sepaDirectDebit,
          creditTransfers: [
            CreditTransferAccount('BE68539007547034'),
            CreditTransferAccount('NL03INGB0004489902'),
          ],
          directDebit: DirectDebit(
            mandateReference: 'MND-1',
            creditorIdentifier: 'BE98ZZZ0123456789',
            debitedAccountIdentifier: 'BE68539007547034',
          ),
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
      final xml = writeCii(invoice);
      expect(
        RegExp('<ram:DirectDebitMandateID>').allMatches(xml),
        hasLength(1),
      );
      expect(
        readCii(xml).paymentInstructions!.directDebit!.mandateReference,
        'MND-1',
      );
    });
  });
}
