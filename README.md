<a alt="ComApps Logo" href="https://comapps.be" target="_blank" rel="noreferrer"><img src="https://www.comapps.be/wp-content/uploads/2026/09/CompleteLogoHorizontalMini.png" style="margin: 15px"></a>

# EN 16931 CII

[![Build](https://img.shields.io/github/actions/workflow/status/raphrmx/en16931_cii/ci.yml?branch=main&label=build)](https://github.com/raphrmx/en16931_cii/actions/workflows/ci.yml)
[![Pub Version](https://img.shields.io/pub/v/en16931_cii?color=blue)](https://pub.dev/packages/en16931_cii)
[![Maintainer](https://img.shields.io/badge/Maintainer-Raphael_Vrient-purple)](https://pub.dev/publishers/comapps.be/packages)
[![License](https://img.shields.io/badge/Licence-MIT-blue)](/LICENSE)
![Maintenance](https://img.shields.io/badge/Maintained-yes-success)

Writes the European electronic invoice as UN/CEFACT CII, the syntax France
and Germany read. Factur-X and XRechnung both sit on it.

## Install

```yaml
dependencies:
  en16931: ^0.1.0
  en16931_cii: ^0.1.0
```

## Write an invoice out

Build it with [en16931](https://pub.dev/packages/en16931), check it, then hand
it over.

```dart
import 'package:en16931/en16931.dart';
import 'package:en16931_cii/en16931_cii.dart';

final invoice = Invoice.fromLines(
  number: '2026-0042',
  issueDate: DateTime(2026, 9, 13),
  dueDate: DateTime(2026, 10, 13),
  seller: const Seller(
    name: 'COMAPPS SRL',
    vatIdentifier: 'BE0123456789',
    electronicAddress: Identifier('0123456749', scheme: Scheme.belgianEnterprise),
    address: Address(city: 'Bruxelles', postalCode: '1000', country: 'BE'),
  ),
  buyer: const Buyer(
    name: 'Client SA',
    electronicAddress: Identifier('0987654394', scheme: Scheme.belgianEnterprise),
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

if (validate(invoice).isEmpty) {
  final xml = writeCii(invoice);
}
```

## Read one back

A supplier invoice goes the other way. What the document does not carry is
left out rather than guessed, so `validate` tells you what the supplier got
wrong instead of the reader hiding it.

```dart
final received = readCii(xml);

for (final violation in validate(received)) {
  print(violation); // [BR-16] The invoice has no line (BG-25).
}
```

`readCii` throws `CiiFormatException` on three things only: text that is not
XML, a root that is not a CrossIndustryInvoice, and a document with no issue
date. Everything else is read as far as it goes.

## Worth knowing up front

A credit note keeps the same root here, carrying the credit note type code.
The other syntax gives it a root of its own, so code that branches on the root
has nothing to branch on.

Dates are written as YYYYMMDD inside a string element with a format
attribute, not as the ISO date UBL uses.

The currency is stated once for the document. Only the VAT totals carry it
again, which is what lets an invoice state its VAT in a second currency.

## What it does not do

It does not decide what an invoice has to contain: that is the model's
business, and `validate` from [en16931](https://pub.dev/packages/en16931) says
whether it holds up. A country puts its own rules on top of the standard, and
those live in a profile package: Germany reads CII, and
[en16931_xrechnung](https://pub.dev/packages/en16931_xrechnung) holds what it
adds. Sending the document is a different problem again.

## License

MIT.
