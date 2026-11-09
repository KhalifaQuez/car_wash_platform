import 'package:flutter/material.dart';
import '../models/store_info.dart';

class StoreImage extends StatelessWidget {
  final StoreInfo store;
  final BoxFit fit;
  const StoreImage(this.store, {super.key, this.fit = BoxFit.cover});
  @override
  Widget build(BuildContext context) {
    Widget fallback(BuildContext context, Object error, StackTrace? stack) =>
        const ColoredBox(
          color: Color(0xFF292036),
          child: Center(
            child: Icon(
              Icons.storefront_outlined,
              size: 48,
              color: Colors.white54,
            ),
          ),
        );
    return store.imageBytes == null
        ? Image.asset(store.imageAsset, fit: fit, errorBuilder: fallback)
        : Image.memory(
            store.imageBytes!,
            fit: fit,
            errorBuilder: fallback,
            gaplessPlayback: true,
          );
  }
}
