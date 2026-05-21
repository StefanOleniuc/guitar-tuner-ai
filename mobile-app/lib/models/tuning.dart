/// Un acordaj: un set ordonat de note (numele corzilor de la groasă la
/// subțire). Acordajele aparțin unui [Instrument] — vezi instrument.dart.
class Tuning {
  const Tuning({required this.name, required this.notes});

  final String name;
  final List<String> notes;
}
