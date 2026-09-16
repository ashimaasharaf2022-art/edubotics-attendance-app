import 'package:flutter/material.dart';

class WorkoraLogo extends StatelessWidget {
  const WorkoraLogo({
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/workora_logo.png',
      width: width,
      height: height,
      fit: fit,
      semanticLabel: 'Workora logo',
    );
  }
}