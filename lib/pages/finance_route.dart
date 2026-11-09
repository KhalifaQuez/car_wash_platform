import 'package:flutter/material.dart';

Future<T?> openFinancePage<T>(
  BuildContext context,
  Widget page,
  Duration enter,
  Duration leave,
) => Navigator.of(context).push<T>(
  PageRouteBuilder<T>(
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : enter,
    reverseTransitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : leave,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOutCubic,
          ),
          child: child,
        ),
  ),
);
