/// Oferta de desconto para quem antecipa uma mensalidade
/// (ex.: janeiro/2027 pago em novembro/dezembro de 2026).
class EarlyPaymentOffer {
  final String id, title, description, discountType, referenceLabel;
  final String discountLabel, audience;
  final int academicYear, referenceMonth;
  final double discountValue;
  final DateTime? endDate, paymentDeadline;
  final List<EarlyPaymentStudentQuote> students;

  const EarlyPaymentOffer({
    required this.id,
    required this.title,
    required this.description,
    required this.discountType,
    required this.referenceLabel,
    required this.discountLabel,
    required this.audience,
    required this.academicYear,
    required this.referenceMonth,
    required this.discountValue,
    this.endDate,
    this.paymentDeadline,
    this.students = const [],
  });

  factory EarlyPaymentOffer.fromJson(Map<String, dynamic> j) =>
      EarlyPaymentOffer(
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        description: '${j['description'] ?? ''}',
        discountType: '${j['discountType'] ?? 'PERCENTAGE'}',
        referenceLabel: '${j['referenceLabel'] ?? ''}',
        discountLabel: '${j['discountLabel'] ?? ''}',
        audience: '${j['audience'] ?? 'ALL'}',
        academicYear: (j['academicYear'] as num?)?.toInt() ?? 0,
        referenceMonth: (j['referenceMonth'] as num?)?.toInt() ?? 1,
        discountValue: (j['discountValue'] as num?)?.toDouble() ?? 0,
        endDate: DateTime.tryParse('${j['endDate'] ?? ''}')?.toLocal(),
        paymentDeadline:
            DateTime.tryParse('${j['paymentDeadline'] ?? ''}')?.toLocal(),
        students: ((j['students'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) =>
                EarlyPaymentStudentQuote.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  /// "10% off" / "R$ 50 off" — curto, para o selo do popup.
  String get shortDiscount => discountType == 'FIXED'
      ? 'R\$ ${discountValue.toStringAsFixed(discountValue % 1 == 0 ? 0 : 2).replaceAll('.', ',')} off'
      : '${discountValue.toStringAsFixed(discountValue % 1 == 0 ? 0 : 1).replaceAll('.', ',')}% off';
}

class EarlyPaymentStudentQuote {
  final String studentId, fullName;
  final double? originalAmount, discountAmount, finalAmount;
  final bool joined;
  const EarlyPaymentStudentQuote({
    required this.studentId,
    required this.fullName,
    this.originalAmount,
    this.discountAmount,
    this.finalAmount,
    this.joined = false,
  });
  factory EarlyPaymentStudentQuote.fromJson(Map<String, dynamic> j) =>
      EarlyPaymentStudentQuote(
        studentId: '${j['studentId']}',
        fullName: '${j['fullName'] ?? ''}',
        originalAmount: (j['originalAmount'] as num?)?.toDouble(),
        discountAmount: (j['discountAmount'] as num?)?.toDouble(),
        finalAmount: (j['finalAmount'] as num?)?.toDouble(),
        joined: j['adhesion'] != null,
      );
}
