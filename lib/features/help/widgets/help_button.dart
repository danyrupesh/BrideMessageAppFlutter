import 'package:flutter/material.dart';
import 'help_sheet.dart';

class HelpButton extends StatelessWidget {
  final String topicId;
  final Color? color;

  const HelpButton({
    super.key,
    required this.topicId,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: TextButton(
        onPressed: () => HelpSheet.show(context, topicId),
        style: TextButton.styleFrom(
          backgroundColor: color ?? Colors.red.withValues(alpha: 0.1),
          foregroundColor: color ?? Colors.redAccent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(
              color: (color ?? Colors.redAccent).withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          visualDensity: VisualDensity.compact,
        ),
        child: Text(
          'Help',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isWide ? 15 : 13,
          ),
        ),
      ),
    );
  }
}
