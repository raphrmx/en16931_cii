import 'package:en16931/en16931.dart';
import 'package:en16931_cii/src/reader.dart';
import 'package:xml/xml.dart';

/// Something a document carries that the semantic model has no room for.
final class SkippedElement {
  /// [count] occurrences of [name] were seen and not read.
  const SkippedElement(this.name, this.count);

  /// The element, as the document names it.
  final String name;

  /// How many of them the document carries.
  final int count;

  /// What the element is for, in words.
  String get purpose => ciiElementsBeyondTheModel[name] ?? 'unknown';

  @override
  String toString() => '$count x $name ($purpose)';
}

/// A document read, and what reading it left behind.
final class CiiRead {
  /// The [invoice] that was read, and the elements [skipped] getting there.
  const CiiRead({required this.invoice, required this.skipped});

  /// The invoice, exactly as `readCii` would give it.
  final Invoice invoice;

  /// What the document carried that the model cannot hold.
  final List<SkippedElement> skipped;

  /// Whether the document gave up everything it had.
  bool get isComplete => skipped.isEmpty;
}

/// The elements this package looks for, and what each one is.
///
/// The list is shorter than the UBL one, and for a reason: a line under a
/// line is written in CII by nesting the line element inside itself, so there
/// is no separate name to look for. XRechnung does not accept it in this
/// syntax at all, which is what its own BR-DEX-15 warns about.
///
/// The list grows when a case turns up. It is deliberately short: a narrow
/// signal that is true beats a wide one that cries wolf over every element
/// the reader is right to ignore.
const Map<String, String> ciiElementsBeyondTheModel = {
  'ram:IncludedSupplyChainTradeLineItem':
      'a line under a line, which EN 16931 has no term for and XRechnung does '
      'not accept in this syntax',
};

/// [document] read into an invoice, with what was left behind.
///
/// `readCii` gives back the invoice and says nothing about what it could not
/// take. That silence is fine for a document written to the standard and a
/// trap for one written beyond it: a line with children comes back without
/// them, adds up, and passes.
///
/// Throws the same [CiiFormatException] as `readCii`, on the same three
/// things.
CiiRead readCiiReporting(String document) {
  final invoice = readCii(document);
  final XmlDocument parsed;
  try {
    parsed = XmlDocument.parse(document);
  } on XmlException {
    // readCii has already refused anything that is not XML.
    return CiiRead(invoice: invoice, skipped: const []);
  }

  // A line is nested when one of its ancestors is a line as well. Counting
  // the element outright would count every ordinary line of the invoice.
  const line = 'ram:IncludedSupplyChainTradeLineItem';
  var nested = 0;
  for (final element in parsed.descendantElements) {
    if (element.name.qualified != line) continue;
    if (!element.ancestorElements.any((e) => e.name.qualified == line)) {
      continue;
    }
    nested++;
  }

  return CiiRead(
    invoice: invoice,
    skipped: [if (nested > 0) SkippedElement(line, nested)],
  );
}
