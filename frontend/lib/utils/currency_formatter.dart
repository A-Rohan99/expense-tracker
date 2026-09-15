/// Utility helper to format currency amounts for the CRED-like UI.
///
/// Supports Indian Rupee numbering format (Lakhs/Crores) as well as
/// standard number formatting, signed strings, and compact notations.
library;

class CurrencyFormatter {
  CurrencyFormatter._();

  /// Formats a numeric value into Indian currency representation.
  /// Example: 1234567.89 -> "₹12,34,567.89" or "₹12,34,568"
  static String format(
    num amount, {
    String symbol = '₹',
    bool showDecimals = false,
    bool showSign = false,
  }) {
    final isNegative = amount < 0;
    final absVal = amount.abs();

    final fixedStr = absVal.toStringAsFixed(showDecimals ? 2 : 0);
    final parts = fixedStr.split('.');
    final integerPart = parts[0];
    final decimalPart = parts.length > 1 ? '.${parts[1]}' : '';

    final formattedInt = _formatIndianInteger(integerPart);

    final sign = isNegative
        ? '-'
        : (showSign && amount > 0 ? '+' : '');

    return '$sign$symbol$formattedInt$decimalPart';
  }

  /// Compact representation for tight spaces (e.g. 1.2L, 45K).
  static String formatCompact(num amount, {String symbol = '₹'}) {
    final isNegative = amount < 0;
    final absVal = amount.abs();
    final sign = isNegative ? '-' : '';

    if (absVal >= 10000000) {
      return '$sign$symbol${(absVal / 10000000).toStringAsFixed(1)}Cr';
    } else if (absVal >= 100000) {
      return '$sign$symbol${(absVal / 100000).toStringAsFixed(1)}L';
    } else if (absVal >= 1000) {
      return '$sign$symbol${(absVal / 1000).toStringAsFixed(1)}k';
    }
    return '$sign$symbol${absVal.toStringAsFixed(0)}';
  }

  static String _formatIndianInteger(String digits) {
    if (digits.length <= 3) return digits;

    final lastThree = digits.substring(digits.length - 3);
    var remaining = digits.substring(0, digits.length - 3);

    final chunks = <String>[];
    while (remaining.length > 2) {
      chunks.insert(0, remaining.substring(remaining.length - 2));
      remaining = remaining.substring(0, remaining.length - 2);
    }
    if (remaining.isNotEmpty) {
      chunks.insert(0, remaining);
    }

    return '${chunks.join(',')},$lastThree';
  }
}
