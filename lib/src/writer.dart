import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:en16931/en16931.dart';
import 'package:en16931_cii/src/reader.dart' show vatPointDateCodeFor;
import 'package:xml/xml.dart';

/// The CII invoice namespace, D16B.
const String ciiInvoice =
    'urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100';

const String _ram =
    'urn:un:unece:uncefact:data:standard:'
    'ReusableAggregateBusinessInformationEntity:100';
const String _udt =
    'urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100';

/// The tax scheme VAT is written under.
const String _vat = 'VAT';

/// The format a CII date is written in, which is YYYYMMDD.
const String _dateFormat = '102';

/// Writes [invoice] as a CII D16B document.
///
/// CII has one root for every document: a credit note is an invoice carrying
/// the credit note type code, where UBL gives it a root of its own. It also
/// splits the invoice in two, the lines on one side and the header on the
/// other, so a line and the totals it feeds sit far apart in the file.
String writeCii(Invoice invoice, {bool pretty = true}) {
  final currency = invoice.currency;
  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0" encoding="UTF-8"');
  builder.element(
    'CrossIndustryInvoice',
    namespaceUri: ciiInvoice,
    nest: () {
      builder.namespaceUri('rsm', ciiInvoice);
      builder.namespaceUri('ram', _ram);
      builder.namespaceUri('udt', _udt);
      _context(builder, invoice);
      _document(builder, invoice);
      builder.element(
        'SupplyChainTradeTransaction',
        namespaceUri: ciiInvoice,
        nest: () {
          for (final line in invoice.lines) {
            _line(builder, line, currency);
          }
          _agreement(builder, invoice);
          _delivery(builder, invoice);
          _settlement(builder, invoice, currency);
        },
      );
    },
  );

  final document = builder.buildDocument();
  return pretty
      ? document.toXmlString(
          pretty: true,
          indent: '  ',
          preserveWhitespace: _significantWhitespace,
        )
      : document.toXmlString();
}

/// Whether the space inside an element is part of what it says.
///
/// Printing an XML document for a human to read reflows the text inside it,
/// which is harmless everywhere but one place. Germany writes a discount for
/// early payment into the payment terms (BT-20) and reads it back line by
/// line, so reflowing that element turns a valid invoice into one that breaks
/// BR-DE-18.
bool _significantWhitespace(XmlNode node) =>
    node is XmlElement &&
    node.name.local == 'Description' &&
    node.parentElement?.name.local == 'SpecifiedTradePaymentTerms';

// --- What the document is --------------------------------------------------

void _context(XmlBuilder b, Invoice invoice) {
  b.element(
    'ExchangedDocumentContext',
    namespaceUri: ciiInvoice,
    nest: () {
      if (invoice.businessProcess != null) {
        _group(b, 'BusinessProcessSpecifiedDocumentContextParameter', () {
          _text(b, 'ID', invoice.businessProcess);
        });
      }
      _group(b, 'GuidelineSpecifiedDocumentContextParameter', () {
        _text(b, 'ID', invoice.specificationIdentifier);
      });
    },
  );
}

void _document(XmlBuilder b, Invoice invoice) {
  b.element(
    'ExchangedDocument',
    namespaceUri: ciiInvoice,
    nest: () {
      _text(b, 'ID', invoice.number);
      _text(b, 'TypeCode', invoice.typeCode.value);
      _date(b, 'IssueDateTime', invoice.issueDate);
      for (final note in invoice.notes) {
        _group(b, 'IncludedNote', () {
          _text(b, 'Content', note.text);
          _text(b, 'SubjectCode', note.subjectCode);
        });
      }
    },
  );
}

// --- One line --------------------------------------------------------------

void _line(XmlBuilder b, InvoiceLine line, String currency) {
  _group(b, 'IncludedSupplyChainTradeLineItem', () {
    _group(b, 'AssociatedDocumentLineDocument', () {
      _text(b, 'LineID', line.id);
      if (line.note != null) {
        _group(b, 'IncludedNote', () => _text(b, 'Content', line.note));
      }
    });
    _product(b, line.item);
    _lineAgreement(b, line, currency);
    _group(b, 'SpecifiedLineTradeDelivery', () {
      _quantity(b, 'BilledQuantity', line.quantity, line.unit);
    });
    _lineSettlement(b, line, currency);
  });
}

void _product(XmlBuilder b, Item item) {
  _group(b, 'SpecifiedTradeProduct', () {
    _identifier(b, 'GlobalID', item.standardIdentifier);
    _text(b, 'SellerAssignedID', item.sellerIdentifier);
    _text(b, 'BuyerAssignedID', item.buyerIdentifier);
    _text(b, 'Name', item.name);
    _text(b, 'Description', item.description);
    for (final attribute in item.attributes) {
      _group(b, 'ApplicableProductCharacteristic', () {
        _text(b, 'Description', attribute.name);
        _text(b, 'Value', attribute.value);
      });
    }
    for (final classification in item.classificationIdentifiers) {
      _group(b, 'DesignatedProductClassification', () {
        _identifier(b, 'ClassCode', classification, scheme: 'listID');
      });
    }
    if (item.originCountry != null) {
      _group(b, 'OriginTradeCountry', () {
        _text(b, 'ID', item.originCountry);
      });
    }
  });
}

void _lineAgreement(XmlBuilder b, InvoiceLine line, String currency) {
  _group(b, 'SpecifiedLineTradeAgreement', () {
    if (line.buyerOrderLineReference != null) {
      _group(b, 'BuyerOrderReferencedDocument', () {
        _text(b, 'LineID', line.buyerOrderLineReference);
      });
    }
    final price = line.price;
    if (price.grossPrice != null) {
      _group(b, 'GrossPriceProductTradePrice', () {
        _amount(b, 'ChargeAmount', price.grossPrice, exactScale: true);
        if (price.baseQuantity != null) {
          _quantity(
            b,
            'BasisQuantity',
            price.baseQuantity!,
            price.baseQuantityUnit,
          );
        }
        if (price.discount != null) {
          _group(b, 'AppliedTradeAllowanceCharge', () {
            _indicator(b, charge: false);
            _amount(b, 'ActualAmount', price.discount, exactScale: true);
          });
        }
      });
    }
    _group(b, 'NetPriceProductTradePrice', () {
      _amount(b, 'ChargeAmount', price.netPrice, exactScale: true);
      if (price.baseQuantity != null) {
        _quantity(
          b,
          'BasisQuantity',
          price.baseQuantity!,
          price.baseQuantityUnit,
        );
      }
    });
  });
}

void _lineSettlement(XmlBuilder b, InvoiceLine line, String currency) {
  _group(b, 'SpecifiedLineTradeSettlement', () {
    _group(b, 'ApplicableTradeTax', () {
      _text(b, 'TypeCode', _vat);
      _text(b, 'CategoryCode', line.vatCategory.code);
      if (line.vatRate != null) {
        _text(b, 'RateApplicablePercent', line.vatRate.toString());
      }
    });
    _period(b, line.period);
    for (final entry in line.allowancesAndCharges) {
      _group(b, 'SpecifiedTradeAllowanceCharge', () {
        _indicator(b, charge: entry.kind == AllowanceOrCharge.charge);
        if (entry.percentage != null) {
          _text(b, 'CalculationPercent', entry.percentage.toString());
        }
        _amount(b, 'BasisAmount', entry.baseAmount);
        _amount(b, 'ActualAmount', entry.amount);
        _text(b, 'ReasonCode', entry.reasonCode);
        _text(b, 'Reason', entry.reason);
      });
    }
    _group(b, 'SpecifiedTradeSettlementLineMonetarySummation', () {
      _amount(b, 'LineTotalAmount', line.netAmount);
    });
    if (line.objectIdentifier != null) {
      _group(b, 'AdditionalReferencedDocument', () {
        _identifier(b, 'IssuerAssignedID', line.objectIdentifier);
        _text(b, 'TypeCode', '130');
      });
    }
    if (line.buyerAccountingReference != null) {
      _group(b, 'ReceivableSpecifiedTradeAccountingAccount', () {
        _text(b, 'ID', line.buyerAccountingReference);
      });
    }
  });
}

// --- The header ------------------------------------------------------------

void _agreement(XmlBuilder b, Invoice invoice) {
  _group(b, 'ApplicableHeaderTradeAgreement', () {
    _text(b, 'BuyerReference', invoice.buyerReference);
    _party(b, 'SellerTradeParty', _sellerParty(invoice.seller));
    _party(b, 'BuyerTradeParty', _buyerParty(invoice.buyer));
    final representative = invoice.taxRepresentative;
    if (representative != null) {
      _party(
        b,
        'SellerTaxRepresentativeTradeParty',
        _Party(
          name: representative.name,
          address: representative.address,
          vatIdentifier: representative.vatIdentifier,
        ),
      );
    }
    if (invoice.purchaseOrderReference != null ||
        invoice.salesOrderReference != null) {
      if (invoice.salesOrderReference != null) {
        _group(b, 'SellerOrderReferencedDocument', () {
          _text(b, 'IssuerAssignedID', invoice.salesOrderReference);
        });
      }
      if (invoice.purchaseOrderReference != null) {
        _group(b, 'BuyerOrderReferencedDocument', () {
          _text(b, 'IssuerAssignedID', invoice.purchaseOrderReference);
        });
      }
    }
    if (invoice.contractReference != null) {
      _group(b, 'ContractReferencedDocument', () {
        _text(b, 'IssuerAssignedID', invoice.contractReference);
      });
    }
    for (final document in invoice.supportingDocuments) {
      _group(b, 'AdditionalReferencedDocument', () {
        _text(b, 'IssuerAssignedID', document.reference);
        _text(b, 'URIID', document.externalUri?.toString());
        _text(b, 'TypeCode', '916');
        _text(b, 'Name', document.description);
        final attachment = document.attachment;
        if (attachment != null) {
          b.element(
            'AttachmentBinaryObject',
            namespaceUri: _ram,
            attributes: {
              'mimeCode': attachment.mimeCode,
              'filename': attachment.filename,
            },
            nest: base64Encode(attachment.bytes),
          );
        }
      });
    }
    if (invoice.objectIdentifier != null) {
      _group(b, 'AdditionalReferencedDocument', () {
        _identifier(b, 'IssuerAssignedID', invoice.objectIdentifier);
        _text(b, 'TypeCode', '130');
      });
    }
    if (invoice.tenderReference != null) {
      _group(b, 'AdditionalReferencedDocument', () {
        _text(b, 'IssuerAssignedID', invoice.tenderReference);
        _text(b, 'TypeCode', '50');
      });
    }
    if (invoice.projectReference != null) {
      _group(b, 'SpecifiedProcuringProject', () {
        _text(b, 'ID', invoice.projectReference);
        _text(b, 'Name', 'Project reference');
      });
    }
  });
}

void _delivery(XmlBuilder b, Invoice invoice) {
  final delivery = invoice.delivery;
  _group(b, 'ApplicableHeaderTradeDelivery', () {
    if (delivery != null &&
        (delivery.name != null ||
            delivery.address != null ||
            delivery.locationIdentifier != null)) {
      _group(b, 'ShipToTradeParty', () {
        _identifier(b, 'ID', delivery.locationIdentifier);
        _text(b, 'Name', delivery.name);
        if (delivery.address != null) {
          _address(b, delivery.address!);
        }
      });
    }
    if (delivery?.date != null) {
      _group(b, 'ActualDeliverySupplyChainEvent', () {
        _date(b, 'OccurrenceDateTime', delivery!.date!);
      });
    }
    if (invoice.despatchAdviceReference != null) {
      _group(b, 'DespatchAdviceReferencedDocument', () {
        _text(b, 'IssuerAssignedID', invoice.despatchAdviceReference);
      });
    }
    if (invoice.receivingAdviceReference != null) {
      _group(b, 'ReceivingAdviceReferencedDocument', () {
        _text(b, 'IssuerAssignedID', invoice.receivingAdviceReference);
      });
    }
  });
}

void _settlement(XmlBuilder b, Invoice invoice, String currency) {
  _group(b, 'ApplicableHeaderTradeSettlement', () {
    final debit = invoice.paymentInstructions?.directDebit;
    _text(b, 'CreditorReferenceID', debit?.creditorIdentifier);
    _text(
      b,
      'PaymentReference',
      invoice.paymentInstructions?.remittanceInformation,
    );
    _text(b, 'TaxCurrencyCode', invoice.vatAccountingCurrency);
    _text(b, 'InvoiceCurrencyCode', currency);
    final payee = invoice.payee;
    if (payee != null) {
      _party(
        b,
        'PayeeTradeParty',
        _Party(
          name: payee.name,
          identifier: payee.identifier,
          legalRegistrationIdentifier: payee.legalRegistrationIdentifier,
        ),
      );
    }
    _paymentMeans(b, invoice);
    _tradeTax(b, invoice, currency);
    _period(b, invoice.invoicingPeriod, name: 'BillingSpecifiedPeriod');
    for (final entry in invoice.allowancesAndCharges) {
      _group(b, 'SpecifiedTradeAllowanceCharge', () {
        _indicator(b, charge: entry.kind == AllowanceOrCharge.charge);
        if (entry.percentage != null) {
          _text(b, 'CalculationPercent', entry.percentage.toString());
        }
        _amount(b, 'BasisAmount', entry.baseAmount);
        _amount(b, 'ActualAmount', entry.amount);
        _text(b, 'ReasonCode', entry.reasonCode);
        _text(b, 'Reason', entry.reason);
        _group(b, 'CategoryTradeTax', () {
          _text(b, 'TypeCode', _vat);
          _text(b, 'CategoryCode', entry.vatCategory.code);
          if (entry.vatRate != null) {
            _text(b, 'RateApplicablePercent', entry.vatRate.toString());
          }
        });
      });
    }
    if (invoice.paymentTerms != null ||
        invoice.dueDate != null ||
        debit?.mandateReference != null) {
      _group(b, 'SpecifiedTradePaymentTerms', () {
        _text(b, 'Description', invoice.paymentTerms);
        if (invoice.dueDate != null) {
          _date(b, 'DueDateDateTime', invoice.dueDate!);
        }
        _text(b, 'DirectDebitMandateID', debit?.mandateReference);
      });
    }
    _summation(b, invoice, currency);
    for (final preceding in invoice.precedingInvoices) {
      _group(b, 'InvoiceReferencedDocument', () {
        _text(b, 'IssuerAssignedID', preceding.reference);
        if (preceding.issueDate != null) {
          _date(
            b,
            'FormattedIssueDateTime',
            preceding.issueDate!,
            formatted: true,
          );
        }
      });
    }
    if (invoice.buyerAccountingReference != null) {
      _group(b, 'ReceivableSpecifiedTradeAccountingAccount', () {
        _text(b, 'ID', invoice.buyerAccountingReference);
      });
    }
  });
}

void _paymentMeans(XmlBuilder b, Invoice invoice) {
  final instructions = invoice.paymentInstructions;
  if (instructions == null) return;
  _group(b, 'SpecifiedTradeSettlementPaymentMeans', () {
    _text(b, 'TypeCode', instructions.means.value);
    _text(b, 'Information', instructions.meansText);
    final card = instructions.card;
    if (card != null) {
      _group(b, 'ApplicableTradeSettlementFinancialCard', () {
        _text(b, 'ID', card.primaryAccountNumber);
        _text(b, 'CardholderName', card.holderName);
      });
    }
    final debit = instructions.directDebit;
    if (debit?.debitedAccountIdentifier != null) {
      _group(b, 'PayerPartyDebtorFinancialAccount', () {
        _text(b, 'IBANID', debit!.debitedAccountIdentifier);
      });
    }
    for (final account in instructions.creditTransfers) {
      _group(b, 'PayeePartyCreditorFinancialAccount', () {
        _text(b, 'IBANID', account.identifier);
        _text(b, 'AccountName', account.name);
      });
      if (account.providerBic != null) {
        _group(b, 'PayeeSpecifiedCreditorFinancialInstitution', () {
          _text(b, 'BICID', account.providerBic);
        });
      }
    }
  });
}

void _tradeTax(XmlBuilder b, Invoice invoice, String currency) {
  for (final entry in invoice.vatBreakdown) {
    _group(b, 'ApplicableTradeTax', () {
      _amount(b, 'CalculatedAmount', entry.taxAmount);
      _text(b, 'TypeCode', _vat);
      _text(b, 'ExemptionReason', entry.exemptionReason);
      _amount(b, 'BasisAmount', entry.taxableAmount);
      _text(b, 'CategoryCode', entry.category.code);
      _text(b, 'ExemptionReasonCode', entry.exemptionReasonCode);
      if (invoice.vatPointDateCode != null) {
        _text(
          b,
          'DueDateTypeCode',
          vatPointDateCodeFor(invoice.vatPointDateCode),
        );
      }
      if (entry.rate != null) {
        _text(b, 'RateApplicablePercent', entry.rate.toString());
      }
    });
  }
}

void _summation(XmlBuilder b, Invoice invoice, String currency) {
  final totals = invoice.totals;
  _group(b, 'SpecifiedTradeSettlementHeaderMonetarySummation', () {
    _amount(b, 'LineTotalAmount', totals.sumOfLineNetAmounts);
    _amount(b, 'ChargeTotalAmount', totals.sumOfCharges);
    _amount(b, 'AllowanceTotalAmount', totals.sumOfAllowances);
    _amount(b, 'TaxBasisTotalAmount', totals.totalWithoutVat);
    if (totals.totalVat != null) {
      _amount(b, 'TaxTotalAmount', totals.totalVat, currency: currency);
    }
    final accounting = totals.totalVatInAccountingCurrency;
    if (accounting != null && invoice.vatAccountingCurrency != null) {
      _amount(
        b,
        'TaxTotalAmount',
        accounting,
        currency: invoice.vatAccountingCurrency,
      );
    }
    _amount(b, 'RoundingAmount', totals.roundingAmount);
    _amount(b, 'GrandTotalAmount', totals.totalWithVat);
    _amount(b, 'TotalPrepaidAmount', totals.paidAmount);
    _amount(b, 'DuePayableAmount', totals.amountDueForPayment);
  });
}

// --- Parties ---------------------------------------------------------------

/// What CII writes for any party, whichever role it plays.
class _Party {
  const _Party({
    required this.name,
    this.address,
    this.identifier,
    this.identifiers = const [],
    this.legalRegistrationIdentifier,
    this.vatIdentifier,
    this.taxRegistrationIdentifier,
    this.electronicAddress,
    this.contact,
    this.tradingName,
  });

  final String name;
  final Address? address;
  final Identifier? identifier;
  final List<Identifier> identifiers;
  final Identifier? legalRegistrationIdentifier;
  final String? vatIdentifier;
  final String? taxRegistrationIdentifier;
  final Identifier? electronicAddress;
  final Contact? contact;
  final String? tradingName;
}

_Party _sellerParty(Seller seller) => _Party(
  name: seller.name,
  tradingName: seller.tradingName,
  address: seller.address,
  identifiers: seller.identifiers,
  legalRegistrationIdentifier: seller.legalRegistrationIdentifier,
  vatIdentifier: seller.vatIdentifier,
  taxRegistrationIdentifier: seller.taxRegistrationIdentifier,
  electronicAddress: seller.electronicAddress,
  contact: seller.contact,
);

_Party _buyerParty(Buyer buyer) => _Party(
  name: buyer.name,
  address: buyer.address,
  identifier: buyer.identifier,
  legalRegistrationIdentifier: buyer.legalRegistrationIdentifier,
  vatIdentifier: buyer.vatIdentifier,
  electronicAddress: buyer.electronicAddress,
  contact: buyer.contact,
);

void _party(XmlBuilder b, String name, _Party party) {
  _group(b, name, () {
    for (final identifier in [
      ...party.identifiers,
      if (party.identifier != null) party.identifier!,
    ]) {
      _identifier(b, 'ID', identifier);
    }
    _text(b, 'Name', party.name);
    if (party.tradingName != null ||
        party.legalRegistrationIdentifier != null) {
      _group(b, 'SpecifiedLegalOrganization', () {
        _identifier(b, 'ID', party.legalRegistrationIdentifier);
        _text(b, 'TradingBusinessName', party.tradingName);
      });
    }
    if (party.contact != null) {
      _group(b, 'DefinedTradeContact', () {
        _text(b, 'PersonName', party.contact!.name);
        if (party.contact!.telephone != null) {
          _group(b, 'TelephoneUniversalCommunication', () {
            _text(b, 'CompleteNumber', party.contact!.telephone);
          });
        }
        if (party.contact!.email != null) {
          _group(b, 'EmailURIUniversalCommunication', () {
            _text(b, 'URIID', party.contact!.email);
          });
        }
      });
    }
    if (party.address != null) _address(b, party.address!);
    final electronic = party.electronicAddress;
    if (electronic != null) {
      _group(b, 'URIUniversalCommunication', () {
        b.element(
          'URIID',
          namespaceUri: _ram,
          attributes: {
            if (electronic.scheme != null) 'schemeID': electronic.scheme!,
          },
          nest: electronic.value,
        );
      });
    }
    if (party.vatIdentifier != null) {
      _group(b, 'SpecifiedTaxRegistration', () {
        b.element(
          'ID',
          namespaceUri: _ram,
          attributes: {'schemeID': 'VA'},
          nest: party.vatIdentifier,
        );
      });
    }
    if (party.taxRegistrationIdentifier != null) {
      _group(b, 'SpecifiedTaxRegistration', () {
        b.element(
          'ID',
          namespaceUri: _ram,
          attributes: {'schemeID': 'FC'},
          nest: party.taxRegistrationIdentifier,
        );
      });
    }
  });
}

void _address(XmlBuilder b, Address address) {
  _group(b, 'PostalTradeAddress', () {
    _text(b, 'PostcodeCode', address.postalCode);
    _text(b, 'LineOne', address.line1);
    _text(b, 'LineTwo', address.line2);
    _text(b, 'LineThree', address.line3);
    _text(b, 'CityName', address.city);
    _text(b, 'CountryID', address.country);
    _text(b, 'CountrySubDivisionName', address.countrySubdivision);
  });
}

// --- Writing one element ---------------------------------------------------

void _group(XmlBuilder b, String name, void Function() nest) {
  b.element(name, namespaceUri: _ram, nest: nest);
}

void _text(XmlBuilder b, String name, String? value) {
  if (value == null) return;
  b.element(name, namespaceUri: _ram, nest: value);
}

void _indicator(XmlBuilder b, {required bool charge}) {
  _group(b, 'ChargeIndicator', () {
    b.element('Indicator', namespaceUri: _udt, nest: '$charge');
  });
}

void _identifier(
  XmlBuilder b,
  String name,
  Identifier? identifier, {
  String scheme = 'schemeID',
}) {
  if (identifier == null) return;
  b.element(
    name,
    namespaceUri: _ram,
    attributes: {if (identifier.scheme != null) scheme: identifier.scheme!},
    nest: identifier.value,
  );
}

void _quantity(XmlBuilder b, String name, Decimal value, UnitCode? unit) {
  b.element(
    name,
    namespaceUri: _ram,
    attributes: {if (unit != null) 'unitCode': unit.value},
    nest: value.toString(),
  );
}

/// Writes a date the way CII writes one, which is YYYYMMDD under a format
/// attribute rather than the ISO date the other syntax uses.
void _date(
  XmlBuilder b,
  String name,
  CalendarDate date, {
  bool formatted = false,
}) {
  b.element(
    name,
    namespaceUri: _ram,
    nest: () {
      b.element(
        formatted ? 'DateTimeString' : 'DateTimeString',
        namespaceUri: _udt,
        attributes: {'format': _dateFormat},
        nest:
            '${date.year.toString().padLeft(4, '0')}'
            '${date.month.toString().padLeft(2, '0')}'
            '${date.day.toString().padLeft(2, '0')}',
      );
    },
  );
}

/// Writes a monetary amount.
///
/// CII leaves the currency off every amount but the VAT totals, because the
/// document states it once. A unit price keeps the decimals it was given.
void _amount(
  XmlBuilder b,
  String name,
  Decimal? value, {
  String? currency,
  bool exactScale = false,
}) {
  if (value == null) return;
  b.element(
    name,
    namespaceUri: _ram,
    attributes: {'currencyID': ?currency},
    nest: exactScale ? value.toString() : value.toStringAsFixed(2),
  );
}

void _period(XmlBuilder b, DatePeriod? period, {String? name}) {
  if (period == null) return;
  if (period.start == null && period.end == null) return;
  _group(b, name ?? 'BillingSpecifiedPeriod', () {
    if (period.start != null) _date(b, 'StartDateTime', period.start!);
    if (period.end != null) _date(b, 'EndDateTime', period.end!);
  });
}
