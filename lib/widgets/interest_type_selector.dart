import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../models/interest_type.dart';

class InterestTypeSelector extends StatelessWidget {
  const InterestTypeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          constraints.maxWidth >=
              280 * MediaQuery.textScalerOf(context).scale(12) / 12
          ? 4
          : 2;
      const spacing = 6.0;
      final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final type in InterestType.values)
            SizedBox(
              width: width,
              child: Semantics(
                button: true,
                selected: value == type.name,
                child: InkWell(
                  onTap: () => onChanged(type.name),
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: value == type.name
                          ? AppColors.warning.withValues(alpha: 0.15)
                          : AppColors.inputFill,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: value == type.name
                            ? AppColors.warning
                            : AppColors.cardBorder,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      type.label,
                      style: TextStyle(
                        color: value == type.name
                            ? AppColors.warning
                            : AppColors.whiteTertiary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
