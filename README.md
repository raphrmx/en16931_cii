# EN 16931 CII

[![Live demo](https://img.shields.io/badge/Live_demo-packages.comapps.be-3c9a70)](https://packages.comapps.be/en16931/)
[![Pub Version](https://img.shields.io/pub/v/en16931_cii?color=0175C2)](https://pub.dev/packages/en16931_cii)
[![Build](https://img.shields.io/github/actions/workflow/status/raphrmx/en16931_cii/ci.yml?branch=main&label=build)](https://github.com/raphrmx/en16931_cii/actions/workflows/ci.yml)
![Maintainer](https://img.shields.io/badge/Maintainer-Raphael_Vrient-733d90)
[![Licence](https://img.shields.io/badge/Licence-MIT-8C6A3F)](LICENSE)
![Platforms](https://img.shields.io/badge/Platforms-Android,_iOS,_macOS,_Windows,_Linux,_Web-22375C.svg)
[![Donate with PayPal](https://img.shields.io/badge/Donate-PayPal-00457C?logo=paypal&logoColor=white)](https://www.paypal.com/donate/?hosted_button_id=ZN6D382YQAV5N)

Writes the European electronic invoice as UN/CEFACT CII, the syntax France
and Germany read. Factur-X and XRechnung both sit on it.

## Install

```yaml
dependencies:
  en16931: ^0.1.2
  en16931_cii: ^0.1.3
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

A document written beyond the standard is read as far as the standard goes,
and no further. `readCiiReporting` says what was left behind, which matters
more than it sounds: an invoice whose lines carry lines of their own comes
back with the parents only, still adds up, and passes.

```dart
final read = readCiiReporting(xml);

for (final element in read.skipped) {
  print(element); // 2 x ram:IncludedSupplyChainTradeLineItem (a line under ...)
}
```

`ciiElementsBeyondTheModel` names what is looked for. It is shorter than the
UBL one for a reason: a line under a line is written here by nesting the line
element inside itself, so there is no separate name to look for.

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
those live in a profile package: France and Germany both read CII, so
[en16931_facturx](https://pub.dev/packages/en16931_facturx) holds the French
levels and the hybrid PDF, and
[en16931_xrechnung](https://pub.dev/packages/en16931_xrechnung) what Germany
adds. Delivery is a separate choice: the same document goes over Peppol,
through a portal, or inside a PDF.

## License

Released under the [MIT licence](https://pub.dev/packages/en16931_cii/license).

## More from COMAPPS

The EN 16931 family:

| Package | What it does |
| --- | --- |
| [en16931](https://pub.dev/packages/en16931) | The semantic model of the European invoice and the rules of the standard. |
| [en16931_ubl](https://pub.dev/packages/en16931_ubl) | Writes and reads it as UBL 2.1. |
| [en16931_peppol](https://pub.dev/packages/en16931_peppol) | The Peppol BIS Billing 3.0 profile. |
| [en16931_xrechnung](https://pub.dev/packages/en16931_xrechnung) | The XRechnung profile, for German public bodies. |
| [en16931_facturx](https://pub.dev/packages/en16931_facturx) | The Factur-X profile and its hybrid PDF. |
| [en16931_ublbe](https://pub.dev/packages/en16931_ublbe) | The UBL.BE profile, for Belgian accounting software. |

Every package COMAPPS publishes is listed at
[packages.comapps.be](https://packages.comapps.be).
