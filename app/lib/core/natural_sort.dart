/// Natural sorting for collector numbers.
///
/// Collector numbers are text, not integers: real values include `12a`, `101★`
/// and `A-45`. A plain string sort puts `10` before `2`, so digit runs are
/// compared numerically and everything else lexically.
library;

final _chunk = RegExp(r'\d+|\D+');

int compareNatural(String a, String b) {
  final left = _chunk.allMatches(a).map((m) => m[0]!).toList();
  final right = _chunk.allMatches(b).map((m) => m[0]!).toList();

  for (var i = 0; i < left.length && i < right.length; i++) {
    final l = left[i];
    final r = right[i];
    final ln = int.tryParse(l);
    final rn = int.tryParse(r);

    final result = (ln != null && rn != null)
        ? ln.compareTo(rn)
        : l.toLowerCase().compareTo(r.toLowerCase());
    if (result != 0) return result;
  }
  return left.length.compareTo(right.length);
}
