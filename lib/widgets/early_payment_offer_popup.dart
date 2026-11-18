import 'package:academyhub_mobile/model/early_payment_offer_model.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _gold = Color(0xFF00A859);
const _goldDark = Color(0xFF047857);
final _shortDate = DateFormat('dd/MM');

/// Remembers, per device, when the family dismissed an offer so the popup
/// does not come back on every visit (it returns after a few days, and the
/// small pill keeps it reachable in the meantime).
class EarlyPaymentOfferMemory {
  static const _prefix = 'early_payment_offer_dismissed_';
  static const quietPeriod = Duration(days: 3);

  static Future<bool> shouldAutoShow(String offerId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final at = prefs.getInt('$_prefix$offerId');
      if (at == null) return true;
      return DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch(at)) >
          quietPeriod;
    } catch (_) {
      return true;
    }
  }

  static Future<void> dismiss(String offerId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          '$_prefix$offerId', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }
}

String earlyPaymentDeadlineText(EarlyPaymentOffer offer) {
  final date = offer.paymentDeadline ?? offer.endDate;
  return date == null ? '' : 'até ${_shortDate.format(date)}';
}

/// Floating card that slides up from the bottom. It never blocks the form:
/// the family can keep filling it in, close it, or accept the offer.
class EarlyPaymentOfferToast extends StatefulWidget {
  const EarlyPaymentOfferToast({
    super.key,
    required this.offer,
    required this.onAccept,
    required this.onDismiss,
    this.accepted = false,
    this.acceptLabel = 'Quero aproveitar',
    this.acceptedMessage =
        'Combinado! Registramos seu interesse junto com a matrícula.',
    this.priceLine,
  });
  final EarlyPaymentOffer offer;
  final VoidCallback onAccept, onDismiss;
  final bool accepted;
  final String acceptLabel, acceptedMessage;
  final String? priceLine;
  @override
  State<EarlyPaymentOfferToast> createState() => _EarlyPaymentOfferToastState();
}

class _EarlyPaymentOfferToastState extends State<EarlyPaymentOfferToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 420))
    ..forward();
  late final Animation<Offset> _slide =
      Tween(begin: const Offset(0, .35), end: Offset.zero)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    await _c.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.offer;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF1E2228) : Colors.white;
    final text = dark ? Colors.white : const Color(0xFF1B1F24);
    final muted = dark ? Colors.white70 : const Color(0xFF5E6672);
    final deadline = earlyPaymentDeadlineText(o);
    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _c,
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _gold.withValues(alpha: .55)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: .14),
                    blurRadius: 22,
                    offset: const Offset(0, 8)),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _GiftBadge(label: o.shortDiscount),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(o.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: text)),
                      const SizedBox(height: 3),
                      Text(
                          widget.accepted
                              ? widget.acceptedMessage
                              : (o.description.isNotEmpty
                                  ? o.description
                                  : '${o.discountLabel} pagando a mensalidade de ${o.referenceLabel} antecipada${deadline.isEmpty ? '' : ' $deadline'}.'),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              fontSize: 12.5, height: 1.35, color: muted)),
                      if (widget.priceLine != null && !widget.accepted) ...[
                        const SizedBox(height: 4),
                        Text(widget.priceLine!,
                            style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: _goldDark)),
                      ],
                      const SizedBox(height: 8),
                      if (widget.accepted)
                        Row(children: [
                          const Icon(Icons.check_circle,
                              color: Color(0xFF00A859), size: 16),
                          const SizedBox(width: 6),
                          Text('Desconto reservado',
                              style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF00A859))),
                        ])
                      else
                        Wrap(spacing: 4, children: [
                          FilledButton(
                            onPressed: widget.onAccept,
                            style: FilledButton.styleFrom(
                              backgroundColor: _gold,
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              textStyle: GoogleFonts.inter(
                                  fontSize: 12.5, fontWeight: FontWeight.w800),
                            ),
                            child: Text(widget.acceptLabel),
                          ),
                          TextButton(
                            onPressed: _close,
                            style: TextButton.styleFrom(
                                foregroundColor: muted,
                                visualDensity: VisualDensity.compact),
                            child: const Text('Agora não'),
                          ),
                        ]),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  visualDensity: VisualDensity.compact,
                  onPressed: _close,
                  icon: Icon(Icons.close_rounded, size: 18, color: muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GiftBadge extends StatefulWidget {
  const _GiftBadge({required this.label});
  final String label;
  @override
  State<_GiftBadge> createState() => _GiftBadgeState();
}

class _GiftBadgeState extends State<_GiftBadge>
    with SingleTickerProviderStateMixin {
  // A single gentle wiggle to draw the eye, then it stays still.
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        AnimatedBuilder(
          animation: _c,
          builder: (_, child) => Transform.rotate(
              angle: (1 - _c.value) *
                  .25 *
                  (((_c.value * 6).floor() % 2 == 0) ? 1 : -1),
              child: child),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF34D399), _gold],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.card_giftcard_rounded,
                color: Colors.white, size: 24),
          ),
        ),
        const SizedBox(height: 4),
        Text(widget.label,
            style: GoogleFonts.inter(
                fontSize: 10.5, fontWeight: FontWeight.w800, color: _goldDark)),
      ]);
}

/// Small pill that keeps the offer reachable after the popup is closed.
class EarlyPaymentOfferPill extends StatelessWidget {
  const EarlyPaymentOfferPill(
      {super.key,
      required this.offer,
      required this.onTap,
      this.accepted = false});
  final EarlyPaymentOffer offer;
  final VoidCallback onTap;
  final bool accepted;
  @override
  Widget build(BuildContext context) => Material(
        color: accepted
            ? const Color(0xFF00A859).withValues(alpha: .12)
            : _gold.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(accepted ? Icons.check_circle : Icons.card_giftcard_rounded,
                  size: 14,
                  color: accepted ? const Color(0xFF00A859) : _goldDark),
              const SizedBox(width: 5),
              Text(
                  accepted
                      ? 'Desconto reservado'
                      : '${offer.shortDiscount} em ${offer.referenceLabel.split('/').first}',
                  style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: accepted ? const Color(0xFF00A859) : _goldDark)),
            ]),
          ),
        ),
      );
}

/// Shows [EarlyPaymentOfferToast] as an overlay at the bottom of the screen,
/// without touching the host layout. Returns a function that removes it.
VoidCallback showEarlyPaymentOfferOverlay(
  BuildContext context, {
  required EarlyPaymentOffer offer,
  required Future<bool> Function() onAccept,
  String? priceLine,
  String acceptLabel = 'Quero aproveitar',
  String acceptedMessage =
      'Pronto! A escola vai enviar as instruções de pagamento.',
}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  var removed = false;
  var accepted = false;
  void remove() {
    if (removed) return;
    removed = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (ctx) => Positioned(
      left: 12,
      right: 12,
      bottom: MediaQuery.of(ctx).padding.bottom + 84,
      child: Center(
        child: StatefulBuilder(
          builder: (ctx, setInner) => EarlyPaymentOfferToast(
            offer: offer,
            accepted: accepted,
            priceLine: priceLine,
            acceptLabel: acceptLabel,
            acceptedMessage: acceptedMessage,
            onAccept: () async {
              final ok = await onAccept();
              if (!ok || removed) return;
              setInner(() => accepted = true);
              Future<void>.delayed(const Duration(milliseconds: 2600), remove);
            },
            onDismiss: () {
              if (!accepted) EarlyPaymentOfferMemory.dismiss(offer.id);
              remove();
            },
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  return remove;
}
