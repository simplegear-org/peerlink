import 'package:flutter/material.dart';

class ActionCircleButton extends StatelessWidget {
  final double size;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const ActionCircleButton({
    super.key,
    required this.size,
    required this.icon,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedBackground =
        backgroundColor ?? Colors.white.withValues(alpha: 0.10);
    final resolvedForeground = foregroundColor ?? Colors.white;

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: resolvedBackground,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Icon(icon, color: resolvedForeground, size: size * 0.42),
      ),
    );
  }
}

class StatPill extends StatelessWidget {
  final String label;
  final String value;
  final double fontSize;
  final Color? valueColor;

  const StatPill({
    super.key,
    required this.label,
    required this.value,
    required this.fontSize,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            color: Colors.white60,
            fontSize: fontSize,
            height: 1.0,
          ),
          children: [
            TextSpan(text: '$label '),
            TextSpan(
              text: value,
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: fontSize,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
