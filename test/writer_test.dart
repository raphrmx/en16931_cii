import 'package:decimal/decimal.dart';
import 'package:en16931/en16931.dart';
import 'package:en16931_cii/en16931_cii.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

const _seller = Seller(
  name: 'COMAPPS SRL',
  vatIdentifier: 'BE0123456789',
  electronicAddress: Identifier('0123456749', scheme: '0208'),
  address: Address(city: 'Bruxelles', postalCode: '1000', country: 'BE'),
);

const _buyer = Buyer(
  name: 'Client SA',
  electronicAddress: Identifier('0987654394', scheme: '0208'),
  address: Address(city: 'Namur', postalCode: '5000', country: 'BE'),
);

Invoice _invoice({
  InvoiceTypeCode? typeCode,
  List<InvoiceLine>? lines,
  List<DocumentAllowanceCharge> allowancesAndCharges = const [],
}) =>
    Invoice.fromLines(
      number: '2026-0042',
      issueDate: DateTime(2026, 9, 13),
      dueDate: DateTime(2026, 10, 13),
      typeCode: typeCode ?? InvoiceTypeCode.commercialInvoice,
      seller: _seller,
      buyer: _buyer,
      allowancesAndCharges: allowancesAndCharges,
      lines: lines ??
          [
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

XmlElement _root(Invoice invoice) =>
    XmlDocument.parse(writeCii(invoice)).rootElement;

XmlElement? _at(XmlElement? root, String path) {
  XmlElement? current = root;
  for (final name in path.split('/')) {
    current = current?.childElements
        .where((element) => element.localName == name)
        .firstOrNull;
  }
  return current;
}

String? _text(XmlElement? root, String path) => _at(root, path)?.innerText;

void main() {
  group('the document', () {
    test('is a cross industry invoice', () {
      final root = _root(_invoice());
      expect(root.localName, 'CrossIndustryInvoice');
      expect(root.namespaceUri, ciiInvoice);
    });

    test('states which specification it follows', () {
      final root = _root(_invoice());
      expect(
        _text(
          root,
          'ExchangedDocumentContext/'
          'GuidelineSpecifiedDocumentContextParameter/ID',
        ),
        en16931Specification,
      );
    });

    test('carries the header terms', () {
      final document = _at(_root(_invoice()), 'ExchangedDocument');
      expect(_text(document, 'ID'), '2026-0042');
      expect(_text(document, 'TypeCode'), '380');
    });

    test('writes a date as YYYYMMDD under a format attribute', () {
      // CII does not write the ISO date the other syntax uses, and a reader
      // that expects one finds nothing.
      final issued = _at(
        _root(_invoice()),
        'ExchangedDocument/IssueDateTime/DateTimeString',
      );
      expect(issued, isNotNull);
      expect(issued!.innerText, '20260913');
      expect(issued.getAttribute('format'), '102');
    });

    test('keeps the three parts in the order the schema fixes', () {
      final names = _root(
        _invoice(),
      ).childElements.map((element) => element.localName).toList();
      expect(names, [
        'ExchangedDocumentContext',
        'ExchangedDocument',
        'SupplyChainTradeTransaction',
      ]);
    });
  });

  group('a line', () {
    XmlElement line() => _at(
          _root(_invoice()),
          'SupplyChainTradeTransaction/IncludedSupplyChainTradeLineItem',
        )!;

    test('carries its identifier and its product', () {
      expect(_text(line(), 'AssociatedDocumentLineDocument/LineID'), '1');
      expect(_text(line(), 'SpecifiedTradeProduct/Name'), 'Consulting');
    });

    test('carries the quantity with its unit', () {
      final quantity = _at(
        line(),
        'SpecifiedLineTradeDelivery/BilledQuantity',
      );
      expect(quantity!.innerText, '8');
      expect(quantity.getAttribute('unitCode'), 'HUR');
    });

    test('carries the net price and the line total', () {
      expect(
        _text(
          line(),
          'SpecifiedLineTradeAgreement/NetPriceProductTradePrice/ChargeAmount',
        ),
        '150',
      );
      expect(
        _text(
          line(),
          'SpecifiedLineTradeSettlement/'
          'SpecifiedTradeSettlementLineMonetarySummation/LineTotalAmount',
        ),
        '1200.00',
      );
    });

    test('carries its VAT under the VAT type code', () {
      final tax =
          _at(line(), 'SpecifiedLineTradeSettlement/ApplicableTradeTax');
      expect(_text(tax, 'TypeCode'), 'VAT');
      expect(_text(tax, 'CategoryCode'), 'S');
      expect(_text(tax, 'RateApplicablePercent'), '21');
    });
  });

  group('the header', () {
    XmlElement settlement() => _at(
          _root(_invoice()),
          'SupplyChainTradeTransaction/ApplicableHeaderTradeSettlement',
        )!;

    test('states the currency once', () {
      expect(_text(settlement(), 'InvoiceCurrencyCode'), 'EUR');
    });

    test('carries the VAT breakdown', () {
      final tax = _at(settlement(), 'ApplicableTradeTax');
      expect(_text(tax, 'CalculatedAmount'), '252.00');
      expect(_text(tax, 'BasisAmount'), '1200.00');
      expect(_text(tax, 'CategoryCode'), 'S');
      expect(_text(tax, 'RateApplicablePercent'), '21');
    });

    test('carries the totals, with the currency only on the VAT', () {
      final totals = _at(
        settlement(),
        'SpecifiedTradeSettlementHeaderMonetarySummation',
      );
      expect(_text(totals, 'LineTotalAmount'), '1200.00');
      expect(_text(totals, 'TaxBasisTotalAmount'), '1200.00');
      expect(_text(totals, 'GrandTotalAmount'), '1452.00');
      expect(_text(totals, 'DuePayableAmount'), '1452.00');
      final vat = _at(totals, 'TaxTotalAmount');
      expect(vat!.innerText, '252.00');
      expect(vat.getAttribute('currencyID'), 'EUR');
      expect(
          _at(totals, 'LineTotalAmount')!.getAttribute('currencyID'), isNull);
    });

    test('carries the seller under a tax registration', () {
      final seller = _at(
        _root(_invoice()),
        'SupplyChainTradeTransaction/ApplicableHeaderTradeAgreement/'
        'SellerTradeParty',
      );
      expect(_text(seller, 'Name'), 'COMAPPS SRL');
      expect(_text(seller, 'PostalTradeAddress/CountryID'), 'BE');
      final registration = _at(seller, 'SpecifiedTaxRegistration/ID');
      expect(registration!.innerText, 'BE0123456789');
      expect(registration.getAttribute('schemeID'), 'VA');
    });

    test('carries the electronic address with its scheme', () {
      final uri = _at(
        _root(_invoice()),
        'SupplyChainTradeTransaction/ApplicableHeaderTradeAgreement/'
        'SellerTradeParty/URIUniversalCommunication/URIID',
      );
      expect(uri!.innerText, '0123456749');
      expect(uri.getAttribute('schemeID'), '0208');
    });

    test('carries the due date under the payment terms', () {
      expect(
        _text(
            settlement(),
            'SpecifiedTradePaymentTerms/DueDateDateTime/'
            'DateTimeString'),
        '20261013',
      );
    });
  });

  group('a document level allowance', () {
    test('is written with its indicator and its VAT category', () {
      final invoice = _invoice(
        allowancesAndCharges: [
          DocumentAllowanceCharge(
            kind: AllowanceOrCharge.allowance,
            amount: Decimal.parse('50.00'),
            vatCategory: VatCategory.standardRate,
            vatRate: Decimal.parse('21'),
            reasonCode: '95',
          ),
        ],
      );
      final entry = _at(
        _root(invoice),
        'SupplyChainTradeTransaction/ApplicableHeaderTradeSettlement/'
        'SpecifiedTradeAllowanceCharge',
      );
      expect(_text(entry, 'ChargeIndicator/Indicator'), 'false');
      expect(_text(entry, 'ActualAmount'), '50.00');
      expect(_text(entry, 'ReasonCode'), '95');
      expect(_text(entry, 'CategoryTradeTax/CategoryCode'), 'S');
    });
  });

  group('a credit note', () {
    test('keeps the same root, unlike the other syntax', () {
      final root = _root(_invoice(typeCode: InvoiceTypeCode.creditNote));
      expect(root.localName, 'CrossIndustryInvoice');
      expect(_text(_at(root, 'ExchangedDocument'), 'TypeCode'), '381');
    });
  });
}
