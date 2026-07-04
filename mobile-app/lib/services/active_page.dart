import 'package:flutter/foundation.dart';

/// Notifier global pentru tab-ul vizibil curent în shell-ul principal.
///
/// Are două surse de adevăr:
///   * `_index`            — pagina activă din `PageView` (Acordor / Metronom).
///   * `_shellInForeground` — există vreo rută pushed peste shell?
///                            (Setări, Auth) — atunci niciun tab nu e vizibil.
///
/// Paginile (Tuner, Metronom) ascultă `visibleIndex` ca să-și gestioneze
/// resursele scumpe (microfon, audio): pornesc cât tab-ul lor e vizibil,
/// se opresc imediat ce nu mai e.
class ActivePage extends ChangeNotifier {
  ActivePage._();
  static final ActivePage instance = ActivePage._();

  static const int tunerIndex = 0;
  static const int metronomeIndex = 1;

  int _index = tunerIndex;
  bool _shellInForeground = true;
  // Default `false` — bara stă ASCUNSĂ pe Acordor până când Tuner confirmă
  // explicit că are acces la microfon (vezi `setBarAllowed(true)`). Așa
  // nu apare un flash de bară peste ecranul de permisiune la prima
  // pornire. Pe celelalte taburi (Metronom, Cont) bara se afișează
  // oricum (`_index != tunerIndex`).
  bool _barAllowed = false;

  // `false` cât timp `TunerScreen._bootstrap()` nu a terminat verificarea
  // permisiunii. Cât e `false`, swipe-ul între taburi e blocat — altfel
  // userul poate glisa pe Metronom SAU Cont în timp ce ecranul de cerere
  // acces microfon e vizibil (dialog de sistem sau full-screen-ul nostru).
  bool _bootstrapDone = false;

  int get index => _index;
  bool get shellInForeground => _shellInForeground;

  /// Index-ul tab-ului vizibil utilizatorului SAU `null` dacă shell-ul
  /// e ascuns de o rută pushed (Setări / Auth / Metronom-screen vechi).
  int? get visibleIndex => _shellInForeground ? _index : null;

  /// `true` cât bara de navigație jos poate fi afișată. `false` cât timp
  /// un ecran ocupă full-screen-ul (ex: ecranul de cerere acces microfon)
  /// — userul are nevoie să vadă conținutul nedistras pe tot ecranul.
  bool get barAllowed => _barAllowed;

  /// `true` după ce `TunerScreen._bootstrap()` a terminat verificarea
  /// permisiunii (indiferent dacă a fost acordată sau nu). Folosit de
  /// `MainShell` pentru a activa swipe-ul între taburi.
  bool get bootstrapDone => _bootstrapDone;

  void setIndex(int v) {
    if (_index == v) return;
    _index = v;
    notifyListeners();
  }

  void setShellInForeground(bool v) {
    if (_shellInForeground == v) return;
    _shellInForeground = v;
    notifyListeners();
  }

  void setBarAllowed(bool v) {
    if (_barAllowed == v) return;
    _barAllowed = v;
    notifyListeners();
  }

  void markBootstrapDone() {
    if (_bootstrapDone) return;
    _bootstrapDone = true;
    notifyListeners();
  }

  // Request explicit de schimbare a tabului
  //
  // În general taburile se schimbă din `PersistentFeatureBar` (tap pe
  // buton) sau prin swipe pe PageView. Există însă cazuri în care un
  // ecran *din interior* (ex. tap pe logo din AuthScreen tab) vrea să
  // ceară shell-ului „du-mă pe tab-ul X". MainShell înregistrează
  // [tabRequestHandler] în initState și îl folosește ca să facă
  // `PageController.jumpToPage`.
  void Function(int)? tabRequestHandler;

  /// Cere shell-ului să navigheze instant la tab-ul [index]. No-op dacă
  /// shell-ul nu a înregistrat un handler (rar — doar dacă MainShell
  /// nu e încă montat).
  void requestTab(int index) {
    final h = tabRequestHandler;
    if (h != null) h(index);
  }
}
