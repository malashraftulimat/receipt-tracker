/// Merges OCR text captured from several overlapping photos of one long
/// receipt (Japanese supermarket receipts are often 30–60 cm long).
///
/// The user photographs the receipt top → bottom in chunks; consecutive images
/// overlap. This class removes the duplicated lines at the seam so the merged
/// text can be fed to the normal `ReceiptParser`.
class ReceiptTextMerger {
  const ReceiptTextMerger();

  /// Default number of lines to look back / ahead when aligning a new chunk.
  static const int defaultMaxOverlap = 25;

  /// Merges [chunks] in capture order (top of the receipt first).
  String merge(List<String> chunks, {int maxOverlap = defaultMaxOverlap}) {
    final result = <String>[];

    for (final chunk in chunks) {
      final lines = _cleanLines(chunk);
      if (lines.isEmpty) continue;

      if (result.isEmpty) {
        result.addAll(lines);
        continue;
      }

      final overlap = _findOverlap(result, lines, maxOverlap);
      result.addAll(lines.skip(overlap));
    }

    return result.join('\n');
  }

  /// Number of lines at the seam that are duplicated, 0 when no overlap.
  int _findOverlap(List<String> existing, List<String> incoming, int maxOverlap) {
    final limit = [
      maxOverlap,
      existing.length,
      incoming.length,
    ].reduce((a, b) => a < b ? a : b);

    for (var size = limit; size >= 1; size--) {
      var matches = true;
      for (var i = 0; i < size; i++) {
        final a = _normalizeLine(existing[existing.length - size + i]);
        final b = _normalizeLine(incoming[i]);
        if (a != b) {
          matches = false;
          break;
        }
      }
      if (matches) return size;
    }
    return 0;
  }

  List<String> _cleanLines(String chunk) {
    final lines = <String>[];
    for (final raw in chunk.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      // Consecutive identical lines are a common OCR artefact on photos.
      if (lines.isNotEmpty && _normalizeLine(lines.last) == _normalizeLine(line)) {
        continue;
      }
      lines.add(line);
    }
    return lines;
  }

  /// Comparison key: ignore spaces, width variants and case.
  String _normalizeLine(String line) {
    final buffer = StringBuffer();
    for (final rune in line.runes) {
      if (rune == 0x3000 || rune == 0x20) continue;
      if (rune >= 0xFF01 && rune <= 0xFF5E) {
        buffer.writeCharCode(rune - 0xFEE0);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString().toLowerCase();
  }
}
