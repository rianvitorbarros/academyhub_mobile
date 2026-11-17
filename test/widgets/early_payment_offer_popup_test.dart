import 'package:academyhub_mobile/model/early_payment_offer_model.dart';
import 'package:academyhub_mobile/widgets/early_payment_offer_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

EarlyPaymentOffer _offer() => EarlyPaymentOffer.fromJson({
      'id': 'o1',
      'title': 'Janeiro 2027 antecipado',
      'description': '',
      'discountType': 'PERCENTAGE',
      'discountValue': 10,
      'referenceLabel': 'janeiro/2027',
      'discountLabel': '10% de desconto',
      'audience': 'ALL',
      'academicYear': 2027,
      'referenceMonth': 1,
      'paymentDeadline': '2026-12-20T12:00:00.000Z',
      'students': [
        {
          'studentId': 's1',
          'fullName': 'Ana Clara',
          'originalAmount': 500,
          'finalAmount': 450,
          'adhesion': null
        }
      ],
    });

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('model parses offer, short label and student quotes', () {
    final offer = _offer();
    expect(offer.shortDiscount, '10% off');
    expect(offer.students.single.finalAmount, 450);
    expect(offer.students.single.joined, isFalse);
    expect(earlyPaymentDeadlineText(offer), 'até 20/12');
  });

  testWidgets('toast offers accept and dismiss without blocking',
      (tester) async {
    var accepted = 0, dismissed = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: EarlyPaymentOfferToast(
            offer: _offer(),
            priceLine: 'R\$ 450,00 em vez de R\$ 500,00',
            onAccept: () => accepted++,
            onDismiss: () => dismissed++,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Janeiro 2027 antecipado'), findsOneWidget);
    expect(find.textContaining('10% de desconto pagando a mensalidade'),
        findsOneWidget);
    expect(find.text('R\$ 450,00 em vez de R\$ 500,00'), findsOneWidget);
    await tester.tap(find.text('Quero aproveitar'));
    expect(accepted, 1);
    await tester.tap(find.text('Agora não'));
    await tester.pumpAndSettle();
    expect(dismissed, 1);
  });

  test('dismissal silences the popup for a few days', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await EarlyPaymentOfferMemory.shouldAutoShow('o1'), isTrue);
    await EarlyPaymentOfferMemory.dismiss('o1');
    expect(await EarlyPaymentOfferMemory.shouldAutoShow('o1'), isFalse);
    expect(await EarlyPaymentOfferMemory.shouldAutoShow('o2'), isTrue);
  });
}
