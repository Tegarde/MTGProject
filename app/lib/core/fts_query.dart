/// FTS5 query escaping.
///
/// FTS5 treats `"`, `*`, `:`, `^`, `-`, `(`, `)` and the bare word `NEAR` as
/// operators. Passing raw user input to MATCH throws on inputs as ordinary as
/// `Jace, the Mind Sculptor`, so every token is quoted before it is used.
library;

/// Converts free text into a safe FTS5 prefix query.
///
/// Returns null when the input has no usable tokens, in which case the caller
/// should fall back to a plain filter query rather than running MATCH.
String? toFtsQuery(String input) {
  final tokens = input
      .split(RegExp(r'[\s,]+'))
      .map((t) => t.replaceAll(RegExp(r'''["*:^()\-]'''), '').trim())
      .where((t) => t.isNotEmpty)
      .map((t) => '"${t.replaceAll('"', '""')}"*');

  final query = tokens.join(' ');
  return query.isEmpty ? null : query;
}
