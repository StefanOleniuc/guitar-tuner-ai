import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/active_page.dart';
import '../services/auth_service.dart';
import '../widgets/app_background.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_logo_banner.dart';

const Color _bg = Color(0xFF060608);
const Color _green = Color(0xFF00E676);
const Color _track = Color(0xFF2A2A2A);
const Color _field = Color(0x14FFFFFF);

enum _Mode { signIn, signUp, reset }

/// Ecran de autentificare — cont opțional (email + parolă).
/// Folosit în două moduri:
///   * **pushed** (default) — din welcome la prima pornire sau din pastila
///     „Sign up" → are buton „Mai târziu" sus-dreapta, propriul background.
///   * **inTab=true** — afișat ca al treilea tab swipeable în `MainShell`
///     când utilizatorul nu e logat → fără „Mai târziu" (swipe-ul îl
///     duce înapoi pe taburile celelalte), fără background propriu
///     (MainShell-ul îl pictează unitar pe sub PageView).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.inTab = false});

  /// `true` când e afișat ca pagină din `PageView` (vs. rută pushed).
  final bool inTab;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // Ecranul se deschide pe „Creează cont" — majoritatea celor care ajung
  // aici nu au încă un cont. Conectarea e oferită discret dedesubt.
  _Mode _mode = _Mode.signUp;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _otp = TextEditingController();
  final _newPassReset = TextEditingController();
  bool _obscure = true;
  bool _obscureNewPass = true;
  bool _resetCodeSent = false;
  bool _loading = false;
  String? _error;

  // Aceeași validare ca pe backend (app/api/auth.py · _EMAIL_RE).
  static final RegExp _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _otp.dispose();
    _newPassReset.dispose();
    super.dispose();
  }

  void _switchMode(_Mode m) {
    setState(() {
      _mode = m;
      _error = null;
      _resetCodeSent = false;
    });
  }

  String? _validate() {
    if (_mode == _Mode.reset && _resetCodeSent) {
      if (_otp.text.trim().length != 6) {
        return 'Introdu codul de 6 cifre primit pe email.';
      }
      if (_newPassReset.text.length < 6) {
        return 'Parola nouă trebuie să aibă cel puțin 6 caractere.';
      }
      return null;
    }
    final email = _email.text.trim();
    if (email.isEmpty || !_emailRe.hasMatch(email)) {
      return 'Introdu o adresă de email validă.';
    }
    if (_mode == _Mode.reset) return null;
    if (_password.text.length < 6) {
      return 'Parola trebuie să aibă cel puțin 6 caractere.';
    }
    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final v = _validate();
    if (v != null) {
      setState(() => _error = v);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    HapticFeedback.selectionClick();

    final auth = AuthService.instance;
    final email = _email.text.trim();

    if (_mode == _Mode.reset) {
      if (!_resetCodeSent) {
        // Pasul 1 — trimitem cerere OTP
        final err = await auth.requestPasswordReset(email);
        if (!mounted) return;
        setState(() => _loading = false);
        if (err != null) {
          setState(() => _error = err);
        } else {
          setState(() => _resetCodeSent = true);
        }
      } else {
        // Pasul 2 — confirmăm codul și setăm parola nouă
        final err = await auth.confirmPasswordReset(
          email,
          _otp.text.trim(),
          _newPassReset.text,
        );
        if (!mounted) return;
        setState(() => _loading = false);
        if (err == null) {
          HapticFeedback.mediumImpact();
          await showAppMessage(
            context,
            icon: Icons.check_circle_outline_rounded,
            title: 'Parolă resetată',
            message:
                'Parola a fost schimbată cu succes. Poți să te conectezi acum.',
          );
          if (mounted) _switchMode(_Mode.signIn);
        } else {
          setState(() => _error = err);
        }
      }
      return;
    }

    final err = _mode == _Mode.signIn
        ? await auth.login(email, _password.text)
        : await auth.register(email, _password.text, _name.text);

    if (!mounted) return;
    setState(() => _loading = false);
    if (err == null) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).maybePop(); // succes → înapoi
    } else {
      setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inTab = widget.inTab;
    return Scaffold(
      backgroundColor: inTab ? Colors.transparent : _bg,
      body: Stack(
        children: [
          // În tab, fundalul îl pictează `MainShell` unitar pe sub PageView
          // — nu mai dublăm AppBackground (s-ar suprapune două radial-glow).
          if (!inTab) const AppBackground(),
          SafeArea(
            child: Column(
              children: [
                // Header personalizat: wordmark „GTune AI" + buton „Mai
                // târziu" (doar dacă ecranul e pushed — în tab nu există
                // rută peste shell ca să o închidem).
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 12, 0),
                  child: Row(
                    children: [
                      // Logo aplicație + wordmark → ecranul nu pare un
                      // template generic de login. În modul „tab" (al
                      // 3-lea tab al shell-ului) e tappable: shortcut
                      // direct la Acordor pentru cine s-a rătăcit aici.
                      InkWell(
                        onTap: inTab
                            ? () => ActivePage.instance.requestTab(
                                ActivePage.tunerIndex,
                              )
                            : null,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                'assets/images/GTune_emblem_transparent.png',
                                width: 34,
                                height: 34,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(width: 10),
                              const AppLogoBanner(fontSize: 18),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (!inTab)
                        TextButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white60,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                          ),
                          child: const Text(
                            'Mai târziu',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
                        children: [
                          _header(),
                          const SizedBox(height: 28),
                          if (_mode == _Mode.signUp) ...[
                            _input(
                              controller: _name,
                              label: 'Nume (opțional)',
                              icon: Icons.person_outline,
                            ),
                            const SizedBox(height: 12),
                          ],
                          _input(
                            controller: _email,
                            label: 'Email',
                            icon: Icons.alternate_email,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          if (_mode == _Mode.reset && _resetCodeSent) ...[
                            const SizedBox(height: 12),
                            _input(
                              controller: _otp,
                              label: 'Cod de resetare (6 cifre)',
                              icon: Icons.pin_outlined,
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 12),
                            _input(
                              controller: _newPassReset,
                              label: 'Parolă nouă',
                              icon: Icons.lock_outline,
                              obscure: _obscureNewPass,
                              trailing: IconButton(
                                icon: Icon(
                                  _obscureNewPass
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: Colors.white38,
                                  size: 20,
                                ),
                                onPressed: () => setState(
                                  () => _obscureNewPass = !_obscureNewPass,
                                ),
                              ),
                            ),
                          ],
                          if (_mode != _Mode.reset) ...[
                            const SizedBox(height: 12),
                            _input(
                              controller: _password,
                              label: 'Parolă',
                              icon: Icons.lock_outline,
                              obscure: _obscure,
                              trailing: IconButton(
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: Colors.white38,
                                  size: 20,
                                ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                          ],
                          if (_mode == _Mode.signIn)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => _switchMode(_Mode.reset),
                                child: const Text(
                                  'Ai uitat parola?',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          // Animat: apariția/dispariția erorii face un slide
                          // smooth în loc de salt brusc al layout-ului.
                          AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            alignment: Alignment.topCenter,
                            child: _error == null
                                ? const SizedBox(width: double.infinity)
                                : Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: _errorBox(_error!),
                                  ),
                          ),
                          const SizedBox(height: 18),
                          _submitButton(),
                          const SizedBox(height: 18),
                          _modeSwitch(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final (icon, title, subtitle) = switch (_mode) {
      _Mode.signIn => (
        Icons.login_rounded,
        'Bine ai revenit',
        'Conectează-te la contul tău GTune AI',
      ),
      _Mode.signUp => (
        Icons.person_add_alt_1_rounded,
        'Creează-ți un cont',
        'Instrument, setări și istoricul sesiunilor tale — sincronizate pe orice telefon',
      ),
      _Mode.reset =>
        _resetCodeSent
            ? (
                Icons.mark_email_read_outlined,
                'Verifică emailul',
                'Cod trimis la ${_email.text.trim()}',
              )
            : (
                Icons.lock_reset_rounded,
                'Resetare parolă',
                'Introdu emailul — îți trimitem un cod de 6 cifre',
              ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Pastila cu icon de cont — gradient + halou verde discret.
        Container(
          width: 78,
          height: 78,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_green.withAlpha(48), _green.withAlpha(16)],
            ),
            border: Border.all(color: _green.withAlpha(110), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: _green.withAlpha(60),
                blurRadius: 24,
                spreadRadius: -6,
              ),
            ],
          ),
          child: Icon(icon, color: _green, size: 36),
        ),
        const SizedBox(height: 22),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 14,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    TextInputType? keyboardType,
    Widget? trailing,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      cursorColor: _green,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38, fontSize: 14),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        suffixIcon: trailing,
        filled: true,
        fillColor: _field,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _track),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _green, width: 1.5),
        ),
      ),
    );
  }

  Widget _errorBox(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF44336).withAlpha(28),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF44336).withAlpha(110)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF6E63), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _submitButton() {
    final label = switch (_mode) {
      _Mode.signIn => 'Conectează-te',
      _Mode.signUp => 'Creează cont',
      _Mode.reset => _resetCodeSent ? 'Confirmă resetarea' : 'Trimite cod',
    };
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: _loading ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: _green,
          foregroundColor: Colors.black,
          disabledBackgroundColor: _green.withAlpha(80),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.black,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
      ),
    );
  }

  Widget _modeSwitch() {
    if (_mode == _Mode.reset) {
      return Center(
        child: TextButton.icon(
          onPressed: () => _switchMode(_Mode.signIn),
          icon: const Icon(Icons.arrow_back, size: 16, color: Colors.white54),
          label: const Text(
            'Înapoi la conectare',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      );
    }
    final isSignIn = _mode == _Mode.signIn;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          isSignIn ? 'Nu ai cont?' : 'Ai deja cont?',
          style: const TextStyle(color: Colors.white38, fontSize: 13),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () => _switchMode(isSignIn ? _Mode.signUp : _Mode.signIn),
          child: Text(
            isSignIn ? 'Creează unul' : 'Conectează-te',
            style: const TextStyle(
              color: _green,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
