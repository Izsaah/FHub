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
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: isCheckedIn
            ? []
            : const [
                BoxShadow(
                  color: Color(0x120D7A68),
                  offset: Offset(0, 10),
                  blurRadius: 24,
                  spreadRadius: -4,
                ),
                BoxShadow(
                  color: Color(0x0DF49D37),
                  offset: Offset(0, 4),
                  blurRadius: 10,
                  spreadRadius: -2,
                ),
              ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isCheckedIn
              ? const Color(0xFFE2EAE7)
              : const Color(0xFF005F50),
          foregroundColor: isCheckedIn ? const Color(0xFF6E7A75) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isCheckedIn
                  ? const Color(0xFFBDC9C4).withValues(alpha: 0.6)
                  : Colors.transparent,
            ),
          ),
          elevation: 0,
        ),
        onPressed: isCheckedIn ? null : onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isCheckedIn ? Icons.check_circle : Icons.task_alt, size: 24),
            const SizedBox(width: 8),
            Text(
              isCheckedIn ? "You're already checked in" : "I'M OK",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
