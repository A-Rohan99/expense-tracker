/// Fluid number counter widget that animates from 0 to target value.
library;

import 'package:flutter/material.dart';

import '../utils/currency_formatter.dart';

class AnimatedAmountCounter extends StatelessWidget {
  const AnimatedAmountCounter({
    super.key,
    required this.amount,
    required this.style,
    this.duration = const Duration(milliseconds: 1400),
    this.curve = Curves.easeOutExpo,
    this.prefix = '₹',
    this.showDecimals = false,
    this.showSign = false,
  });

  final double amount;
  final TextStyle style;
  final Duration duration;
  final Curve curve;
  final String prefix;
  final bool showDecimals;
  final bool showSign;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: amount),
      duration: duration,
      curve: curve,
      builder: (context, value, child) {
        final formatted = CurrencyFormatter.format(
          value,
          symbol: prefix,
          showDecimals: showDecimals,
          showSign: showSign,
        );
        return Text(
          formatted,
          style: style,
        );
      },
    );
  }
}
