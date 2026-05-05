import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final style = context.theme.style;

    return SafeArea(
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              border: .all(color: colors.border, width: style.borderWidth),
              borderRadius: style.borderRadius.md,
              color: colors.primary,
            ),
            child: const Placeholder(),
          ),
        ],
      ),
    );
  }
}
