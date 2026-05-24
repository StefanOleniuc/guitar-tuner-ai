import 'dart:ui';

import 'package:flutter/material.dart';

/// Popup modern, reutilizabil, pentru mesaje către utilizator (erori
/// prietenoase, info). Card întunecat cu sticlă, icon colorat, intrare
/// animată (fade + scale). Limbaj prietenos — fără jargon tehnic.
Future<void> showAppMessage(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  Color accent = const Color(0xFF00E676),
  String buttonLabel = 'Am înțeles',
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withAlpha(170),
    builder: (ctx) => _AppDialog(
      icon: icon,
      title: title,
      message: message,
      accent: accent,
      buttonLabel: buttonLabel,
    ),
  );
}

/// Popup de confirmare cu două butoane (anulează / confirmă). Întoarce
/// `true` dacă utilizatorul a apăsat butonul de confirmare, `false`
/// altfel (anulare sau atingere în afara dialogului).
Future<bool> showAppConfirm(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  Color accent = const Color(0xFFFF8A65), // portocaliu — acțiune atențională
  String confirmLabel = 'Confirmă',
  String cancelLabel = 'Anulează',
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withAlpha(170),
    builder: (ctx) => _AppConfirmDialog(
      icon: icon,
      title: title,
      message: message,
      accent: accent,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
    ),
  );
  return result ?? false;
}

class _AppDialog extends StatelessWidget {
  const _AppDialog({
    required this.icon,
    required this.title,
    required this.message,
    required this.accent,
    required this.buttonLabel,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color accent;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        builder: (context, t, child) => Transform.scale(
          scale: 0.86 + 0.14 * t.clamp(0.0, 1.0),
          child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              decoration: BoxDecoration(
                color: const Color(0xFF18181F).withAlpha(245),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.white.withAlpha(26)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withAlpha(30),
                      border: Border.all(color: accent.withAlpha(90)),
                    ),
                    child: Icon(icon, color: accent, size: 30),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        buttonLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppConfirmDialog extends StatelessWidget {
  const _AppConfirmDialog({
    required this.icon,
    required this.title,
    required this.message,
    required this.accent,
    required this.confirmLabel,
    required this.cancelLabel,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color accent;
  final String confirmLabel;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        builder: (context, t, child) => Transform.scale(
          scale: 0.86 + 0.14 * t.clamp(0.0, 1.0),
          child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              decoration: BoxDecoration(
                color: const Color(0xFF18181F).withAlpha(245),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.white.withAlpha(26)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withAlpha(30),
                      border: Border.all(color: accent.withAlpha(90)),
                    ),
                    child: Icon(icon, color: accent, size: 30),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(color: Colors.white.withAlpha(50)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            cancelLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            confirmLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
