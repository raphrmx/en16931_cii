## 0.1.2

- The README names `en16931_facturx`. France reads CII as well as Germany, and
  the README mentioned only the German profile.
- The licence badge and the licence section point at the licence page on
  pub.dev. The README carries no link off to a code host any more.
- `xml` moves to 7, which raises the Dart floor to 3.11. The writer names a
  namespace by its prefix and its URI in that order, where version 6 took them
  the other way round.

## 0.1.1

- The README names the packages that do what this one does not: the model and
  the rules in `en16931`, and the German profile that reads this syntax.

## 0.1.0

First release.

- `writeCii` writes an EN 16931 invoice out as UN/CEFACT CII D16B, the syntax
  France and Germany read. Factur-X and XRechnung both sit on it.
- `readCii` reads one back. What the document does not carry is left out
  rather than guessed, so `validate` says what the issuer got wrong.
- A credit note keeps the same root here, carrying the credit note type code,
  where the other syntax gives it a root of its own.
- Dates are written as YYYYMMDD under a format attribute, not as the ISO date
  the other syntax uses. A reader expecting one finds nothing.
- The currency is stated once for the document. Only the VAT totals carry it
  again, which is what lets an invoice state its VAT in a second currency.
- Elements are matched on their local name, so a document is read whatever
  prefixes it declares its namespaces under.
- The fifteen CII examples the standard is published with are read, written
  back out unchanged, and break no rule. The one exception is named in the
  test with what is actually wrong with it: XRechnung-O writes its VAT
  exemption reason code in lower case where the list is upper case.
