/// CRED-styled segmented toggle to flip between Private and Household data modes.
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';

class HouseholdToggle extends StatelessWidget {
  const HouseholdToggle({
    super.key,
    required this.isHousehold,
    required this.onChanged,
  });

  final bool isHousehold;
  final ValueChanged<bool> onChanged;

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
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildOption(
            title: 'PRIVATE',
            icon: Icons.lock_outline_rounded,
            isSelected: !isHousehold,
            onTap: () => onChanged(false),
          ),
          _buildOption(
            title: 'HOUSEHOLD',
            icon: Icons.groups_outlined,
            isSelected: isHousehold,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }

  Widget _buildOption({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
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
    );
  }
}
