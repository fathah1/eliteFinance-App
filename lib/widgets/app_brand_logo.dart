import 'package:flutter/material.dart';

class AppBrandLogo extends StatelessWidget {
  const AppBrandLogo({
    super.key,
    this.size = 32,
    this.textSize = 12,
    this.borderRadius = 8,
  });

  final double size;
  final double textSize;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E5EFF), Color(0xFF0B2B87)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x331E5EFF),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        'EC',
        style: TextStyle(
          color: Colors.white,
          fontSize: textSize,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          height: 1,
        ),
      ),
    );
  }
}
