import 'package:flutter/material.dart';

class MobileChartButtons extends StatelessWidget {
  final Color color;
  final Color backdropColor;
  final VoidCallback onSoulStances;
  final VoidCallback onYourBeings;

  const MobileChartButtons({
    super.key,
    required this.color,
    required this.backdropColor,
    required this.onSoulStances,
    required this.onYourBeings,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PillButton(
            label: 'Soul Stances',
            color: color,
            backdropColor: backdropColor,
            onTap: onSoulStances,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PillButton(
            label: 'Your Beings',
            color: color,
            backdropColor: backdropColor,
            onTap: onYourBeings,
          ),
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final Color color;
  final Color backdropColor;
  final VoidCallback onTap;

  const _PillButton({
    required this.label,
    required this.color,
    required this.backdropColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: backdropColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
