/// CRED-styled segmented toggle to flip between Private and Household data modes.
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';

class HouseholdToggle extends StatelessWidget {
  const HouseholdToggle({
    super.key,
    required this.isHousehold,
    required this.onChanged,
    this.expanded = false,
  });

  final bool isHousehold;
  final ValueChanged<bool> onChanged;

  /// Let the two options share the full available width instead of hugging
  /// their labels. Used when the toggle gets a row of its own on a narrow
  /// screen, where hugging would strand it against one edge.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.obsidian,
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: AppColors.subtleBorder),
      ),
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          _fit(_buildOption(
            title: 'PRIVATE',
            icon: Icons.lock_outline_rounded,
            isSelected: !isHousehold,
            onTap: () => onChanged(false),
          )),
          _fit(_buildOption(
            title: 'HOUSEHOLD',
            icon: Icons.groups_outlined,
            isSelected: isHousehold,
            onTap: () => onChanged(true),
          )),
        ],
      ),
    );
  }

  Widget _fit(Widget option) => expanded ? Expanded(child: option) : option;

  Widget _buildOption({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    // Semantics: colour alone conveyed which mode was active, so a screen
    // reader announced two identical unlabelled bits of text. minHeight 44
    // brings the tap target up to the accessible minimum — it was ~30dp.
    return Semantics(
      button: true,
      selected: isSelected,
      // The visible label is display-uppercase; spell it normally for a
      // screen reader rather than having it read out letter by letter.
      label: '${title.toLowerCase()} view',
      // Without this the inner Text's own label merges in and the control
      // announces twice. It also drops the GestureDetector's tap action,
      // so re-declare it here or the control is unusable with a screen
      // reader — visible but not activatable.
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.charcoal : Colors.transparent,
          borderRadius: AppRadius.pillAll,
          border: isSelected
              ? Border.all(color: AppColors.subtleBorder.withValues(alpha: 0.15))
              : Border.all(color: Colors.transparent),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.neonCyan.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? AppColors.neonCyan : AppColors.textTertiary,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: AppTypography.labelSmall.copyWith(
                color: isSelected ? AppColors.textPrimary : AppColors.textTertiary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 1.0,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
