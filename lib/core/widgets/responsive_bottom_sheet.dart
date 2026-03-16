import 'package:flutter/material.dart';

Future<T?> showResponsiveBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  Color? backgroundColor,
  ShapeBorder? shape,
  bool showDragHandle = false,
  bool isDismissible = true,
  bool enableDrag = true,
  Color? barrierColor,
  EdgeInsets dialogInset =
      const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
  double maxWidth = 600,
  double desktopBreakpoint = 700,
}) {
  final isWide = MediaQuery.of(context).size.width >= desktopBreakpoint;

  if (isWide) {
    return showDialog<T>(
      context: context,
      barrierDismissible: isDismissible,
      barrierColor: barrierColor,
      builder: (dialogContext) {
        Widget content = builder(dialogContext);

        if (showDragHandle) {
          content = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(dialogContext)
                      .colorScheme
                      .onSurfaceVariant
                      .withAlpha(100),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(child: content),
            ],
          );
        }

        if (useSafeArea) {
          content = SafeArea(child: content);
        }

        return Dialog(
          insetPadding: dialogInset,
          backgroundColor:
              backgroundColor ?? Theme.of(dialogContext).dialogBackgroundColor,
          shape: shape ??
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: content,
          ),
        );
      },
    );
  }

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    backgroundColor: backgroundColor,
    shape: shape,
    showDragHandle: showDragHandle,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    builder: builder,
  );
}
