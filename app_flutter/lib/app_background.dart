import 'package:flutter/material.dart';

import 'theme.dart';

class AppBackground {
  AppBackground._();

  static final ValueNotifier<String?> imageUrl = ValueNotifier<String?>(null);
}

class AppBackgroundLayer extends StatelessWidget {
  const AppBackgroundLayer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: AppBackground.imageUrl,
      builder: (context, imageUrl, _) => Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: AppColors.paper),
          if (imageUrl != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.18,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}
