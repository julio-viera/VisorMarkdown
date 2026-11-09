import 'package:flutter/material.dart';

/// Pliegue: the selected vector identity, shared with assets/visor-markdown.svg.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 36});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Visor Markdown',
    image: true,
    child: CustomPaint(size: Size.square(size), painter: _LogoPainter()),
  );
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 256, size.height / 256);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(8, 8, 240, 240),
        const Radius.circular(54),
      ),
      Paint()..color = const Color(0xff181e34),
    );
    final left = Path()
      ..moveTo(48, 187)
      ..lineTo(48, 66)
      ..lineTo(78, 66)
      ..lineTo(128, 121)
      ..lineTo(128, 166)
      ..lineTo(81, 114)
      ..lineTo(81, 187)
      ..close();
    final right = Path()
      ..moveTo(128, 121)
      ..lineTo(178, 66)
      ..lineTo(208, 66)
      ..lineTo(208, 187)
      ..lineTo(175, 187)
      ..lineTo(175, 114)
      ..lineTo(128, 166)
      ..close();
    canvas.drawPath(left, Paint()..color = const Color(0xffb09aff));
    canvas.drawPath(right, Paint()..color = const Color(0xff65dfc8));
  }

  @override
  bool shouldRepaint(covariant _LogoPainter oldDelegate) => false;
}
