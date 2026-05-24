/// Utilizatorul autentificat (cont creat cu email + parolă).
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    this.displayName,
  });

  final int id;
  final String email;
  final String? displayName;

  /// Nume de afișat — displayName dacă există, altfel partea din email
  /// dinaintea lui `@`.
  String get label {
    final n = displayName?.trim();
    if (n != null && n.isNotEmpty) return n;
    return email.split('@').first;
  }

  /// Inițiala pentru avatar.
  String get initial =>
      label.isNotEmpty ? label[0].toUpperCase() : '?';

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: (json['id'] as num).toInt(),
        email: json['email'] as String,
        displayName: json['displayName'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'displayName': displayName,
      };
}
