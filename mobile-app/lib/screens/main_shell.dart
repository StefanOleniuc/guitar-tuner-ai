import 'package:flutter/material.dart';

import '../services/active_page.dart';
import '../services/auth_service.dart';
import '../utils/app_logger.dart';
import '../utils/route_observer.dart';
import '../widgets/app_background.dart';
import '../widgets/persistent_feature_bar.dart';
import 'account_screen.dart';
import 'auth_screen.dart';
import 'metronome_screen.dart';
import 'tuner_screen.dart';

/// Shell-ul principal al aplicației: găzduiește `PageView`-ul cu taburile
/// permanente (Acordor, Metronom, plus Cont când userul nu e logat) și
/// bara persistentă de jos.
///
/// Navigarea între taburi se face cu tap pe bara de jos SAU prin swipe
/// lateral. Setările sunt mereu o rută pushed peste shell (din iconul
/// Setări din header).
///
/// **AppBackground** se pictează aici, sub `PageView`, ca să nu existe
/// „cusături" vizuale când swipe-ezi între taburi (gradientul radial nu
/// se rupe la marginea ecranului).
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with RouteAware {
  late final PageController _controller;
  int _index = ActivePage.tunerIndex;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: _index);
    ActivePage.instance.setIndex(_index);
    ActivePage.instance.setShellInForeground(true);
    // Înregistrăm handler-ul prin care ecranele „interioare" (ex. tap
    // pe logo în AuthScreen tab) pot cere navigarea la alt tab.
    ActivePage.instance.tabRequestHandler = (i) {
      if (!mounted) return;
      if (i < 0 || i > 2) return;
      _controller.jumpToPage(i);
    };
    // Dacă userul se loghează în timp ce e pe tab-ul Auth (al 3-lea),
    // PageView pierde acel tab → navigăm pe Acordor.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) appRouteObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    if (ActivePage.instance.tabRequestHandler != null) {
      ActivePage.instance.tabRequestHandler = null;
    }
    _controller.dispose();
    super.dispose();
  }

  // ─── RouteAware: shell pe fundal / în prim-plan ──────────────────────
  @override
  void didPushNext() {
    AppLogger.i('🔶 [MainShell] Rută pushed peste shell — pauză taburi');
    ActivePage.instance.setShellInForeground(false);
  }

  @override
  void didPopNext() {
    AppLogger.i('🚀 [MainShell] Shell revenit în prim-plan');
    ActivePage.instance.setShellInForeground(true);
  }

  void _onPageChanged(int i) {
    if (_index == i) return;
    setState(() => _index = i);
    // visibleIndex e derivat din `index` + `shellInForeground`. Tuner ascultă
    // și oprește mic dacă index != 0 (chiar dacă suntem pe Cont — bine).
    ActivePage.instance.setIndex(i);
  }

  void _onBarTap(int i) {
    if (_index == i) return;
    // Salt instant — userul a apăsat un buton, vrea destinația, nu un
    // tur prin tab-urile intermediare. Swipe-ul lateral animează în
    // continuare normal (cu PageScrollPhysics).
    _controller.jumpToPage(i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060608),
      body: Stack(
        children: [
          // Fundal unitar — radiele se văd continuu, fără cusături la swipe.
          const AppBackground(),
          AnimatedBuilder(
            animation: Listenable.merge([
              AuthService.instance,
              ActivePage.instance,
            ]),
            builder: (context, _) {
              final authed = AuthService.instance.isAuthenticated;
              // Tab-ul „Cont" e MEREU prezent ca a 3-a pagină — își
              // schimbă doar conținutul în funcție de auth (form sign-up
              // dacă nu, profil cu statistici dacă da). Așa swipe-ul
              // funcționează consistent în ambele stări.
              //
              // Swipe-ul e blocat cât `_bootstrapDone == false` (adică
              // exact cât ecranul de aprobare microfon e vizibil) ca
              // userul să nu poată glisa pe Metronom / Cont înainte să
              // răspundă la cererea de permisiune.
              final swipeEnabled = ActivePage.instance.bootstrapDone;
              return PageView(
                controller: _controller,
                onPageChanged: _onPageChanged,
                physics: swipeEnabled
                    ? const PageScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                children: [
                  const TunerScreen(),
                  const MetronomeScreen(),
                  authed
                      ? const AccountScreen(inTab: true)
                      : const AuthScreen(inTab: true),
                ],
              );
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedBuilder(
              animation: Listenable.merge([
                AuthService.instance,
                ActivePage.instance,
              ]),
              builder: (context, _) {
                // Bara e ascunsă în trei cazuri:
                //   1. tastatura e ridicată (user scrie) — altfel ar fi
                //      peste teren și permite tap accidental;
                //   2. tab-ul Cont când userul NU e logat (e ecranul de
                //      sign-up/sign-in, vrem flux focused);
                //   3. tab-ul Acordor înainte de aprobarea microfonului.
                final keyboardUp = MediaQuery.of(context).viewInsets.bottom > 0;
                final authed = AuthService.instance.isAuthenticated;
                final onAuthTab = _index == 2 && !authed;
                final tunerNotReady =
                    _index == ActivePage.tunerIndex &&
                    !ActivePage.instance.barAllowed;
                final showBar = !keyboardUp && !onAuthTab && !tunerNotReady;
                return IgnorePointer(
                  ignoring: !showBar,
                  child: AnimatedSlide(
                    offset: showBar ? Offset.zero : const Offset(0, 1.4),
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: showBar ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: PersistentFeatureBar(
                        activeIndex: _index,
                        onTap: _onBarTap,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
