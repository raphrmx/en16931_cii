import 'dart:convert';
import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:en16931/en16931.dart';
import 'package:xml/xml.dart';

/// A document that is not a CII invoice this package can read.
class CiiFormatException implements FormatException {
  /// A document that could not be read, because of [message].
  const CiiFormatException(this.message, [this.source, this.offset]);

  @override
  final String message;

  @override
  final String? source;

  @override
  final int? offset;

  @override
  String toString() => 'CiiFormatException: $message';
}

/// Reads a CII D16B invoice into the semantic model.
///
/// What the document does not carry is left out rather than guessed, so an
/// invoice missing a term comes back missing it and `validate` says which
/// rule that breaks.
///
/// Throws [CiiFormatException] when the text is not XML, when its root is not
/// a CrossIndustryInvoice, or when it carries no issue date.
Invoice readCii(String xml) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(xml);
  } on XmlException catch (error) {
    throw CiiFormatException('Not XML: ${error.message}');
  }

  final root = document.rootElement;
  if (root.localName != 'CrossIndustryInvoice') {
    throw const CiiFormatException('The root is not a CrossIndustryInvoice');
  }

  final header = _child(root, 'ExchangedDocument');
  final issued = _date(header, 'IssueDateTime');
  if (issued == null) {
    throw const CiiFormatException('The document carries no issue date');
  }

  final transaction = _child(root, 'SupplyChainTradeTransaction');
  final agreement = _child(transaction, 'ApplicableHeaderTradeAgreement');
  final delivery = _child(transaction, 'ApplicableHeaderTradeDelivery');
  final settlement = _child(transaction, 'ApplicableHeaderTradeSettlement');
  final context = _child(root, 'ExchangedDocumentContext');
  final terms = _child(settlement, 'SpecifiedTradePaymentTerms');

  return Invoice(
    number: _text(header, 'ID') ?? '',
    issueDate: issued,
    dueDate: _date(terms, 'DueDateDateTime'),
    typeCode: InvoiceTypeCode(_text(header, 'TypeCode') ?? ''),
    currency: _text(settlement, 'InvoiceCurrencyCode') ?? '',
    specificationIdentifier: _text(
      context,
      'GuidelineSpecifiedDocumentContextParameter/ID',
    ),
    businessProcess: _text(
      context,
      'BusinessProcessSpecifiedDocumentContextParameter/ID',
    ),
    vatAccountingCurrency: _text(settlement, 'TaxCurrencyCode'),
    vatPointDateCode: _text(settlement, 'ApplicableTradeTax/DueDateTypeCode'),
    buyerReference: _text(agreement, 'BuyerReference'),
    buyerAccountingReference: _text(
      settlement,
      'ReceivableSpecifiedTradeAccountingAccount/ID',
    ),
    paymentTerms: _text(terms, 'Description'),
    notes: [
      for (final note in _children(header, 'IncludedNote'))
        InvoiceNote(
          _text(note, 'Content') ?? '',
          subjectCode: _text(note, 'SubjectCode'),
        ),
    ],
    invoicingPeriod: _period(_child(settlement, 'BillingSpecifiedPeriod')),
    purchaseOrderReference: _text(
      agreement,
      'BuyerOrderReferencedDocument/IssuerAssignedID',
    ),
    salesOrderReference: _text(
      agreement,
      'SellerOrderReferencedDocument/IssuerAssignedID',
    ),
    contractReference: _text(
      agreement,
      'ContractReferencedDocument/IssuerAssignedID',
    ),
    projectReference: _text(agreement, 'SpecifiedProcuringProject/ID'),
    despatchAdviceReference: _text(
      delivery,
      'DespatchAdviceReferencedDocument/IssuerAssignedID',
    ),
    receivingAdviceReference: _text(
      delivery,
      'ReceivingAdviceReferencedDocument/IssuerAssignedID',
    ),
    tenderReference: _referenceOfType(agreement, '50'),
    objectIdentifier: _objectIdentifier(agreement),
    precedingInvoices: [
      for (final reference in _children(
        settlement,
        'InvoiceReferencedDocument',
      ))
        PrecedingInvoiceReference(
          _text(reference, 'IssuerAssignedID') ?? '',
          issueDate: _date(reference, 'FormattedIssueDateTime'),
        ),
    ],
    supportingDocuments: _supportingDocuments(agreement),
    seller: _seller(_child(agreement, 'SellerTradeParty')),
    buyer: _buyer(_child(agreement, 'BuyerTradeParty')),
    payee: _payee(_child(settlement, 'PayeeTradeParty')),
    taxRepresentative: _taxRepresentative(
      _child(agreement, 'SellerTaxRepresentativeTradeParty'),
    ),
    delivery: _delivery(delivery),
    paymentInstructions: _payment(settlement),
    allowancesAndCharges: _documentEntries(settlement),
    vatBreakdown: _breakdown(settlement),
    totals: _totals(settlement),
    lines: _lines(transaction),
  );
}

// --- References ------------------------------------------------------------

String? _referenceOfType(XmlElement? agreement, String type) {
  for (final reference in _children(
    agreement,
    'AdditionalReferencedDocument',
  )) {
    if (_text(reference, 'TypeCode') != type) continue;
    return _text(reference, 'IssuerAssignedID');
  }
  return null;
}

Identifier? _objectIdentifier(XmlElement? agreement) {
  for (final reference in _children(
    agreement,
    'AdditionalReferencedDocument',
  )) {
    if (_text(reference, 'TypeCode') != '130') continue;
    return _identifier(reference, 'IssuerAssignedID');
  }
  return null;
}

List<SupportingDocument> _supportingDocuments(XmlElement? agreement) {
  final documents = <SupportingDocument>[];
  for (final reference in _children(
    agreement,
    'AdditionalReferencedDocument',
  )) {
    final type = _text(reference, 'TypeCode');
    if (type == '130' || type == '50') continue;
    final binary = _child(reference, 'AttachmentBinaryObject');
    final uri = _text(reference, 'URIID');
    documents.add(
      SupportingDocument(
        _text(reference, 'IssuerAssignedID') ?? '',
        description: _text(reference, 'Name'),
        externalUri: uri == null ? null : Uri.tryParse(uri),
        attachment: binary == null
            ? null
            : Attachment(
                bytes: Uint8List.fromList(base64Decode(binary.innerText)),
                mimeCode: binary.getAttribute('mimeCode') ?? '',
                filename: binary.getAttribute('filename') ?? '',
              ),
      ),
    );
  }
  return documents;
}

// --- Parties ---------------------------------------------------------------

Seller _seller(XmlElement? party) {
  if (party == null) {
    return const Seller(
      name: '',
      address: Address(country: ''),
    );
  }
  return Seller(
    name: _text(party, 'Name') ?? '',
    tradingName: _text(party, 'SpecifiedLegalOrganization/TradingBusinessName'),
    address: _address(_child(party, 'PostalTradeAddress')),
    identifiers: [
      for (final id in _children(party, 'ID'))
        Identifier(id.innerText.trim(), scheme: id.getAttribute('schemeID')),
    ],
    legalRegistrationIdentifier: _identifier(
      _child(party, 'SpecifiedLegalOrganization'),
      'ID',
    ),
    vatIdentifier: _registration(party, 'VA'),
    taxRegistrationIdentifier: _registration(party, 'FC'),
    electronicAddress: _identifier(
      _child(party, 'URIUniversalCommunication'),
      'URIID',
    ),
    contact: _contact(_child(party, 'DefinedTradeContact')),
  );
}

Buyer _buyer(XmlElement? party) {
  if (party == null) {
    return const Buyer(
      name: '',
      address: Address(country: ''),
    );
  }
  return Buyer(
    name: _text(party, 'Name') ?? '',
    address: _address(_child(party, 'PostalTradeAddress')),
    identifier: _identifier(party, 'ID'),
    legalRegistrationIdentifier: _identifier(
      _child(party, 'SpecifiedLegalOrganization'),
      'ID',
    ),
    vatIdentifier: _registration(party, 'VA'),
    electronicAddress: _identifier(
      _child(party, 'URIUniversalCommunication'),
      'URIID',
    ),
    contact: _contact(_child(party, 'DefinedTradeContact')),
  );
}

Payee? _payee(XmlElement? party) {
  if (party == null) return null;
  return Payee(
    name: _text(party, 'Name') ?? '',
    identifier: _identifier(party, 'ID'),
    legalRegistrationIdentifier: _identifier(
      _child(party, 'SpecifiedLegalOrganization'),
      'ID',
    ),
  );
}

TaxRepresentative? _taxRepresentative(XmlElement? party) {
  if (party == null) return null;
  return TaxRepresentative(
    name: _text(party, 'Name') ?? '',
    vatIdentifier: _registration(party, 'VA') ?? '',
    address: _address(_child(party, 'PostalTradeAddress')),
  );
}

/// The identifier a party registers under one scheme, VA for VAT and FC for
/// the other tax registration.
String? _registration(XmlElement party, String scheme) {
  for (final registration in _children(party, 'SpecifiedTaxRegistration')) {
    final id = _child(registration, 'ID');
    if (id == null || id.getAttribute('schemeID') != scheme) continue;
    return id.innerText.trim();
  }
  return null;
}

Address _address(XmlElement? element) {
  if (element == null) return const Address(country: '');
  return Address(
    country: _text(element, 'CountryID') ?? '',
    line1: _text(element, 'LineOne'),
    line2: _text(element, 'LineTwo'),
    line3: _text(element, 'LineThree'),
    city: _text(element, 'CityName'),
    postalCode: _text(element, 'PostcodeCode'),
    countrySubdivision: _text(element, 'CountrySubDivisionName'),
  );
}

Contact? _contact(XmlElement? element) {
  if (element == null) return null;
  return Contact(
    name: _text(element, 'PersonName'),
    telephone: _text(element, 'TelephoneUniversalCommunication/CompleteNumber'),
    email: _text(element, 'EmailURIUniversalCommunication/URIID'),
  );
}

// --- Delivery and payment --------------------------------------------------

Delivery? _delivery(XmlElement? element) {
  if (element == null) return null;
  final party = _child(element, 'ShipToTradeParty');
  final date = _date(
    _child(element, 'ActualDeliverySupplyChainEvent'),
    'OccurrenceDateTime',
  );
  if (party == null && date == null) return null;
  return Delivery(
    name: party == null ? null : _text(party, 'Name'),
    date: date,
    locationIdentifier: party == null ? null : _identifier(party, 'ID'),
    address: party == null || _child(party, 'PostalTradeAddress') == null
        ? null
        : _address(_child(party, 'PostalTradeAddress')),
  );
}

PaymentInstructions? _payment(XmlElement? settlement) {
  final element = _child(settlement, 'SpecifiedTradeSettlementPaymentMeans');
  if (element == null) return null;
  final card = _child(element, 'ApplicableTradeSettlementFinancialCard');
  final creditor = _text(settlement, 'CreditorReferenceID');
  final mandate = _text(
    settlement,
    'SpecifiedTradePaymentTerms/DirectDebitMandateID',
  );
  final debited = _text(element, 'PayerPartyDebtorFinancialAccount/IBANID');
  return PaymentInstructions(
    means: PaymentMeansCode(_text(element, 'TypeCode') ?? ''),
    meansText: _text(element, 'Information'),
    remittanceInformation: _text(settlement, 'PaymentReference'),
    creditTransfers: [
      for (final account in _children(
        element,
        'PayeePartyCreditorFinancialAccount',
      ))
        CreditTransferAccount(
          _text(account, 'IBANID') ?? '',
          name: _text(account, 'AccountName'),
          providerBic: _text(
            element,
            'PayeeSpecifiedCreditorFinancialInstitution/BICID',
          ),
        ),
    ],
    card: card == null
        ? null
        : PaymentCard(
            _text(card, 'ID') ?? '',
            holderName: _text(card, 'CardholderName'),
          ),
    directDebit: creditor == null && mandate == null && debited == null
        ? null
        : DirectDebit(
            mandateReference: mandate,
            creditorIdentifier: creditor,
            debitedAccountIdentifier: debited,
          ),
  );
}

// --- The figures -----------------------------------------------------------

List<DocumentAllowanceCharge> _documentEntries(XmlElement? settlement) {
  final entries = <DocumentAllowanceCharge>[];
  for (final element in _children(
    settlement,
    'SpecifiedTradeAllowanceCharge',
  )) {
    final tax = _child(element, 'CategoryTradeTax');
    entries.add(
      DocumentAllowanceCharge(
        kind: _isCharge(element)
            ? AllowanceOrCharge.charge
            : AllowanceOrCharge.allowance,
        amount: _decimal(element, 'ActualAmount') ?? Decimal.zero,
        baseAmount: _decimal(element, 'BasisAmount'),
        percentage: _decimal(element, 'CalculationPercent'),
        vatCategory: _category(_text(tax, 'CategoryCode')),
        vatRate: tax == null ? null : _decimal(tax, 'RateApplicablePercent'),
        reason: _text(element, 'Reason'),
        reasonCode: _text(element, 'ReasonCode'),
      ),
    );
  }
  return entries;
}

List<VatBreakdown> _breakdown(XmlElement? settlement) {
  final breakdown = <VatBreakdown>[];
  for (final tax in _children(settlement, 'ApplicableTradeTax')) {
    breakdown.add(
      VatBreakdown(
        category: _category(_text(tax, 'CategoryCode')),
        taxableAmount: _decimal(tax, 'BasisAmount') ?? Decimal.zero,
        taxAmount: _decimal(tax, 'CalculatedAmount') ?? Decimal.zero,
        rate: _decimal(tax, 'RateApplicablePercent'),
        exemptionReason: _text(tax, 'ExemptionReason'),
        exemptionReasonCode: _text(tax, 'ExemptionReasonCode'),
      ),
    );
  }
  return breakdown;
}

InvoiceTotals _totals(XmlElement? settlement) {
  final element = _child(
    settlement,
    'SpecifiedTradeSettlementHeaderMonetarySummation',
  );
  final accountingCurrency = _text(settlement, 'TaxCurrencyCode');
  Decimal? vat;
  Decimal? accounting;
  for (final amount in _children(element, 'TaxTotalAmount')) {
    final currency = amount.getAttribute('currencyID');
    final value = Decimal.tryParse(amount.innerText.trim());
    if (accountingCurrency != null && currency == accountingCurrency) {
      accounting = value;
    }
    vat ??= value;
  }
  if (element == null) {
    return InvoiceTotals(
      sumOfLineNetAmounts: Decimal.zero,
      totalWithoutVat: Decimal.zero,
      totalWithVat: Decimal.zero,
      amountDueForPayment: Decimal.zero,
    );
  }
  return InvoiceTotals(
    sumOfLineNetAmounts: _decimal(element, 'LineTotalAmount') ?? Decimal.zero,
    totalWithoutVat: _decimal(element, 'TaxBasisTotalAmount') ?? Decimal.zero,
    totalWithVat: _decimal(element, 'GrandTotalAmount') ?? Decimal.zero,
    amountDueForPayment: _decimal(element, 'DuePayableAmount') ?? Decimal.zero,
    sumOfAllowances: _decimal(element, 'AllowanceTotalAmount'),
    sumOfCharges: _decimal(element, 'ChargeTotalAmount'),
    paidAmount: _decimal(element, 'TotalPrepaidAmount'),
    roundingAmount: _decimal(element, 'RoundingAmount'),
    totalVat: vat,
    totalVatInAccountingCurrency: accounting,
  );
}

List<InvoiceLine> _lines(XmlElement? transaction) {
  final lines = <InvoiceLine>[];
  for (final element in _children(
    transaction,
    'IncludedSupplyChainTradeLineItem',
  )) {
    final agreement = _child(element, 'SpecifiedLineTradeAgreement');
    final settlement = _child(element, 'SpecifiedLineTradeSettlement');
    final quantity = _child(
      _child(element, 'SpecifiedLineTradeDelivery'),
      'BilledQuantity',
    );
    final tax = _child(settlement, 'ApplicableTradeTax');
    final document = _child(element, 'AssociatedDocumentLineDocument');
    lines.add(
      InvoiceLine(
        id: _text(document, 'LineID') ?? '',
        quantity:
            Decimal.tryParse(quantity?.innerText.trim() ?? '') ?? Decimal.zero,
        unit: UnitCode(quantity?.getAttribute('unitCode') ?? ''),
        netAmount:
            _decimal(
              _child(
                settlement,
                'SpecifiedTradeSettlementLineMonetarySummation',
              ),
              'LineTotalAmount',
            ) ??
            Decimal.zero,
        item: _item(_child(element, 'SpecifiedTradeProduct')),
        price: _price(agreement),
        vatCategory: _category(_text(tax, 'CategoryCode')),
        vatRate: tax == null ? null : _decimal(tax, 'RateApplicablePercent'),
        note: _text(document, 'IncludedNote/Content'),
        objectIdentifier: _lineObject(settlement),
        buyerOrderLineReference: _text(
          agreement,
          'BuyerOrderReferencedDocument/LineID',
        ),
        buyerAccountingReference: _text(
          settlement,
          'ReceivableSpecifiedTradeAccountingAccount/ID',
        ),
        period: _period(_child(settlement, 'BillingSpecifiedPeriod')),
        allowancesAndCharges: [
          for (final entry in _children(
            settlement,
            'SpecifiedTradeAllowanceCharge',
          ))
            LineAllowanceCharge(
              kind: _isCharge(entry)
                  ? AllowanceOrCharge.charge
                  : AllowanceOrCharge.allowance,
              amount: _decimal(entry, 'ActualAmount') ?? Decimal.zero,
              baseAmount: _decimal(entry, 'BasisAmount'),
              percentage: _decimal(entry, 'CalculationPercent'),
              reason: _text(entry, 'Reason'),
              reasonCode: _text(entry, 'ReasonCode'),
            ),
        ],
      ),
    );
  }
  return lines;
}

Identifier? _lineObject(XmlElement? settlement) {
  for (final reference in _children(
    settlement,
    'AdditionalReferencedDocument',
  )) {
    if (_text(reference, 'TypeCode') != '130') continue;
    return _identifier(reference, 'IssuerAssignedID');
  }
  return null;
}

Item _item(XmlElement? element) {
  if (element == null) return const Item(name: '');
  return Item(
    name: _text(element, 'Name') ?? '',
    description: _text(element, 'Description'),
    sellerIdentifier: _text(element, 'SellerAssignedID'),
    buyerIdentifier: _text(element, 'BuyerAssignedID'),
    standardIdentifier: _identifier(element, 'GlobalID'),
    classificationIdentifiers: [
      for (final classification in _children(
        element,
        'DesignatedProductClassification',
      ))
        ?_identifier(classification, 'ClassCode', scheme: 'listID'),
    ],
    originCountry: _text(element, 'OriginTradeCountry/ID'),
    attributes: [
      for (final property in _children(
        element,
        'ApplicableProductCharacteristic',
      ))
        ItemAttribute(
          _text(property, 'Description') ?? '',
          _text(property, 'Value') ?? '',
        ),
    ],
  );
}

Price _price(XmlElement? agreement) {
  final net = _child(agreement, 'NetPriceProductTradePrice');
  final gross = _child(agreement, 'GrossPriceProductTradePrice');
  final quantity = _child(net, 'BasisQuantity');
  final unit = quantity?.getAttribute('unitCode');
  return Price(
    netPrice: _decimal(net, 'ChargeAmount') ?? Decimal.zero,
    grossPrice: gross == null ? null : _decimal(gross, 'ChargeAmount'),
    discount: gross == null
        ? null
        : _decimal(
            _child(gross, 'AppliedTradeAllowanceCharge'),
            'ActualAmount',
          ),
    baseQuantity: quantity == null
        ? null
        : Decimal.tryParse(quantity.innerText.trim()),
    baseQuantityUnit: unit == null ? null : UnitCode(unit),
  );
}

/// Whether an allowance or charge element is a charge.
bool _isCharge(XmlElement element) =>
    _text(element, 'ChargeIndicator/Indicator') == 'true';

/// The VAT category [code] names, standard rated when it names none.
VatCategory _category(String? code) => code == null
    ? VatCategory.standardRate
    : VatCategory.tryParse(code) ?? VatCategory.standardRate;

// --- Reading one element ---------------------------------------------------

XmlElement? _child(XmlElement? element, String path) {
  XmlElement? current = element;
  for (final name in path.split('/')) {
    if (current == null) return null;
    current = current.childElements
        .where((child) => child.localName == name)
        .firstOrNull;
  }
  return current;
}

Iterable<XmlElement> _children(XmlElement? element, String name) =>
    element == null
    ? const []
    : element.childElements.where((child) => child.localName == name);

String? _text(XmlElement? element, String path) {
  final found = _child(element, path);
  if (found == null) return null;
  final text = found.innerText.trim();
  return text.isEmpty ? null : text;
}

Decimal? _decimal(XmlElement? element, String path) {
  final text = _text(element, path);
  return text == null ? null : Decimal.tryParse(text);
}

/// A CII date, which is written as YYYYMMDD inside a string element.
CalendarDate? _date(XmlElement? element, String path) {
  final wrapper = _child(element, path);
  if (wrapper == null) return null;
  final text = wrapper.innerText.trim();
  if (text.length != 8) return CalendarDate.tryParse(text);
  return CalendarDate.tryParse(
    '${text.substring(0, 4)}-${text.substring(4, 6)}-${text.substring(6, 8)}',
  );
}

DatePeriod? _period(XmlElement? element) {
  if (element == null) return null;
  final start = _date(element, 'StartDateTime');
  final end = _date(element, 'EndDateTime');
  if (start == null && end == null) return null;
  return DatePeriod(start: start, end: end);
}

Identifier? _identifier(
  XmlElement? element,
  String path, {
  String scheme = 'schemeID',
}) {
  final found = _child(element, path);
  if (found == null) return null;
  final value = found.innerText.trim();
  if (value.isEmpty) return null;
  return Identifier(value, scheme: found.getAttribute(scheme));
}
