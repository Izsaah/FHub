import 'package:flutter/material.dart';

class CheckInButton extends StatelessWidget {
  final bool isCheckedIn;
  final VoidCallback onPressed;

  const CheckInButton({
    super.key,
    required this.isCheckedIn,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 68,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: isCheckedIn
            ? []
            : const [
                BoxShadow(
                  color: Color(0x280D7A68),
                  offset: Offset(0, 8),
                  blurRadius: 20,
                  spreadRadius: 0,
                ),
                BoxShadow(
                  color: Color(0x18005F50),
                  offset: Offset(0, 2),
                  blurRadius: 6,
                  spreadRadius: 0,
                ),
              ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isCheckedIn
              ? const Color(0xFFE8EEEC)
              : const Color(0xFF005F50),
          foregroundColor: isCheckedIn ? const Color(0xFF4A6B63) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isCheckedIn
                  ? const Color(0xFFB5CAC4)
                  : const Color(0xFF0D7A68),
              width: 1.5,
            ),
          ),
          elevation: isCheckedIn ? 0 : 2,
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isCheckedIn ? Icons.check_circle_rounded : Icons.check_circle_outline,
              size: 28,
              color: isCheckedIn ? const Color(0xFF005F50) : Colors.white,
            ),
            const SizedBox(width: 10),
            Text(
              isCheckedIn ? "You're already checked in" : "✓ I'M OK",
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                letterSpacing: isCheckedIn ? 0 : 0.8,
                color: isCheckedIn ? const Color(0xFF234D43) : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
