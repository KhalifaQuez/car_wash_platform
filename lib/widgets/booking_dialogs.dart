import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

class BookingPopupRoute<T> extends RawDialogRoute<T> {
  final Duration returnDuration;
  BookingPopupRoute({
    required WidgetBuilder builder,
    required Duration enterDuration,
    required this.returnDuration,
  }) : super(
         pageBuilder: (context, animation, secondaryAnimation) =>
             builder(context),
         barrierDismissible: true,
         barrierLabel: '关闭悬浮窗',
         barrierColor: const Color(0x66000000),
         transitionDuration: enterDuration,
         transitionBuilder: (context, animation, secondaryAnimation, child) {
           final curved = animation.drive(
             CurveTween(curve: Curves.easeInOutCubic),
           );
           return FadeTransition(
             opacity: curved,
             child: SlideTransition(
               position: Tween<Offset>(
                 begin: const Offset(0, 0.06),
                 end: Offset.zero,
               ).animate(curved),
               child: child,
             ),
           );
         },
       );
  @override
  Duration get reverseTransitionDuration => returnDuration;
}

Future<T?> showBookingPopup<T>(
  BuildContext context,
  WidgetBuilder builder,
  Duration enterDuration,
  Duration returnDuration,
) async {
  final route = BookingPopupRoute<T>(
    builder: builder,
    enterDuration: enterDuration,
    returnDuration: returnDuration,
  );
  final result = await Navigator.of(context).push<T>(route);
  await route.completed;
  return result;
}

class BookingPopupSurface extends StatelessWidget {
  final Widget child;
  const BookingPopupSurface({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.all(24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xF02D203E),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0x667B609F)),
            ),
            child: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(22), child: child),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<bool> confirmBookingAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = '返回',
  required Duration enterDuration,
  required Duration returnDuration,
}) async =>
    await showBookingPopup<bool>(
      context,
      (context) => _BookingConfirm(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
      ),
      enterDuration,
      returnDuration,
    ) ==
    true;

class _BookingConfirm extends StatefulWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  const _BookingConfirm({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
  });
  @override
  State<_BookingConfirm> createState() => _BookingConfirmState();
}

class _BookingConfirmState extends State<_BookingConfirm> {
  bool _closing = false;
  void _close(bool result) {
    if (_closing || ModalRoute.of(context)?.isCurrent != true) return;
    setState(() => _closing = true);
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) => BookingPopupSurface(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Text(
          widget.message,
          style: const TextStyle(height: 1.7, color: Color(0xFFD8CBE7)),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            OutlinedButton(
              onPressed: _closing ? null : () => _close(false),
              child: Text(widget.cancelLabel),
            ),
            FilledButton(
              onPressed: _closing ? null : () => _close(true),
              child: Text(widget.confirmLabel),
            ),
          ],
        ),
      ],
    ),
  );
}
