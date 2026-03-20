import 'package:flutter/material.dart';

/// Desktop breakpoint — same as main_scaffold.dart
const kDesktopBreakpoint = 900.0;

/// Shows a modal bottom sheet on mobile, a centered dialog on desktop.
Future<T?> showAdaptiveSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext) builder,
  bool isScrollControlled = true,
  double maxDialogWidth = 480,
}) {
  final width = MediaQuery.sizeOf(context).width;

  if (width >= kDesktopBreakpoint) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxDialogWidth, maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
          child: builder(ctx),
        ),
      ),
    );
  }

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: builder,
  );
}

/// Whether current screen is desktop-wide.
bool isDesktop(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
