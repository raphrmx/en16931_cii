## 0.1.3

- Several payment accounts (BG-17 repeated) are written and read. CII carries
  one account to a payment means, so an invoice offering two writes the group
  twice; both sides put them all in one group, which lost the second bank
  along the way.
- `readCiiReporting` gives back the invoice and what the document carried that
  the model has no room for. A line under a line is written in CII by nesting
  the line element inside itself, so an ordinary line is not mistaken for one.
  `ciiElementsBeyondTheModel` names what is looked for.

## 0.1.2

- The README names `en16931_facturx`. France reads CII as well as Germany, and
  the README mentioned only the German profile.
- The licence badge and the licence section point at the licence page on
  pub.dev. The README carries no link off to a code host any more.
- `xml` moves to 7, which raises the Dart floor to 3.11. The writer names a
  namespace by its prefix and its URI in that order, where version 6 took them
  the other way round.
- The seller contact point (BT-41) is read from a department as well as from
  a person, the payment account identifier (BT-84) from an account number as
  well as from an IBAN, and the payment terms (BT-20) keep their whitespace.
- The VAT point date code (BT-8) is translated between the two lists. CII
  carries it as a UNTDID 2475 code where the standard draws it from
  UNCL 2005, so a document saying 5 means 3, and passing the one through as
  the other refused the invoice under BR-CL-06.
- The payment terms keep their line breaks through the printer as well. A
  pretty printed document reflows the text inside it, which is harmless
  everywhere but here, and turned a valid German invoice into one that breaks
  BR-DE-18.

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
