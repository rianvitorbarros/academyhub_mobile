double? parseReportCardScore(String input, String label) {
  final value = input.trim();
  if (value.isEmpty) return null;
  final normalized = value.replaceAll(',', '.');
  final score = double.tryParse(normalized);
  if (score == null || !score.isFinite || score < 0 || score > 10) {
    throw FormatException('$label deve ser uma nota numérica entre 0 e 10.');
  }
  return score;
}
