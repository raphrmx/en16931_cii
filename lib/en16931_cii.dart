/// UN/CEFACT CII for the European electronic invoice.
///
/// CII is the second of the two syntaxes EN 16931 is written in, and the one
/// France and Germany read: Factur-X and XRechnung both sit on it. This
/// library writes the semantic model out as CII and reads it back, and
/// nothing else.
library;

export 'src/reader.dart' show CiiFormatException, readCii;
export 'src/writer.dart' show ciiInvoice, writeCii;
