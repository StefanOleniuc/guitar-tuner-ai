import 'package:flutter/widgets.dart';

/// Observer global de rute, înregistrat în `MaterialApp.navigatorObservers`.
///
/// TunerScreen îl folosește (ca `RouteAware`) ca să elibereze microfonul
/// automat ori de câte ori se deschide alt ecran peste tuner (Setări,
/// Metronom, ...) și să-l repornească la întoarcere — fără să cuplăm
/// fiecare ecran de logica microfonului.
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
