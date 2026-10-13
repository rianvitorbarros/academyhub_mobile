import 'package:academyhub_mobile/util/report_card_score_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notas válidas mantêm zero e precisão decimal', () {
    for (final value in ['0', '5', '5,5', '6', '7', '7,5', '10']) {
      expect(parseReportCardScore(value, 'Atividade'),
          double.parse(value.replaceAll(',', '.')));
    }
    expect(parseReportCardScore('7.0', 'Atividade'), 7);
    expect(parseReportCardScore('7,55', 'Atividade'), 7.55);
    expect(parseReportCardScore('  ', 'Atividade'), isNull);
  });

  test('texto e valores fora do limite indicam o campo', () {
    for (final value in ['--', 'abc', '-1', '11', 'NaN']) {
      expect(
          () => parseReportCardScore(value, 'Atividade'),
          throwsA(isA<FormatException>().having(
              (error) => error.message, 'mensagem', contains('Atividade'))));
    }
  });
}
