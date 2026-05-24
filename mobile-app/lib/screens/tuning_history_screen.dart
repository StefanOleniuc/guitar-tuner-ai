import 'dart:math' show max;

import 'package:flutter/material.dart';

import '../models/tuning_session.dart';
import '../services/user_data_service.dart';
import '../widgets/app_background.dart';
import '../widgets/top_header_fade.dart';

const Color _bg = Color(0xFF0D0D0D);
const Color _green = Color(0xFF00E676);
const Color _track = Color(0xFF2A2A2A);

/// Lista de sesiuni de acordaj înregistrate de utilizator. Disponibilă
/// doar când e logat — accesată din secțiunea Cont a Setărilor.
class TuningHistoryScreen extends StatefulWidget {
  const TuningHistoryScreen({super.key});

  @override
  State<TuningHistoryScreen> createState() => _TuningHistoryScreenState();
}

class _TuningHistoryScreenState extends State<TuningHistoryScreen> {
  List<TuningSession>? _sessions; // null = loading
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await UserDataService.instance.fetchHistory(limit: 50);
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _total = UserDataService.instance.historyTotal;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    return Scaffold(
      backgroundColor: _bg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Istoric acordaje',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.3),
        ),
      ),
      body: Stack(
        children: [
          const AppBackground(),
          if (sessions == null)
            const Center(
              child: CircularProgressIndicator(color: _green, strokeWidth: 2.4),
            )
          else if (sessions.isEmpty)
            _buildEmptyState()
          else
            RefreshIndicator(
              color: _green,
              backgroundColor: const Color(0xFF161616),
              onRefresh: _load,
              child: ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  18,
                  MediaQuery.of(context).padding.top + kToolbarHeight + 12,
                  18,
                  32,
                ),
                itemCount: sessions.length + 2,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  if (i == 0) return _buildSummary(sessions);
                  if (i == 1) return _SevenDayChart(sessions: sessions);
                  return _SessionTile(session: sessions[i - 2]);
                },
              ),
            ),
          const TopHeaderFade(color: _bg),
        ],
      ),
    );
  }

  Widget _buildSummary(List<TuningSession> sessions) {
    final completed = sessions.where((s) => s.isComplete).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: _green.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _green.withAlpha(60)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bar_chart_rounded, color: _green, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_total ${_total == 1 ? 'sesiune' : 'sesiuni'} înregistrate',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$completed acordaje complete în istoricul afișat',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _green.withAlpha(24),
                border: Border.all(color: _green.withAlpha(80)),
              ),
              child: const Icon(
                Icons.queue_music_rounded,
                color: _green,
                size: 36,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Niciun acordaj salvat încă',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Acordează-ți instrumentul în Tuner și sesiunile complete '
              'vor apărea aici automat.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white60,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final TuningSession session;

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'acum';
    if (diff.inMinutes < 60) return 'acum ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'acum ${diff.inHours} h';
    if (diff.inDays < 7) return 'acum ${diff.inDays} zile';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final complete = session.isComplete;
    final color = complete ? _green : Colors.orange;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        // Sesiunile complete primesc un fundal verde subtil + border verde
        // — același limbaj vizual ca starea „in tune" din tuner.
        color: complete ? _green.withAlpha(14) : const Color(0x10FFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: complete ? _green.withAlpha(65) : _track),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withAlpha(28),
              shape: BoxShape.circle,
              border: Border.all(color: color.withAlpha(120)),
            ),
            child: Icon(
              complete ? Icons.check_rounded : Icons.timelapse_rounded,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${_instrumentLabel(session.instrument)} · ${session.tuningName}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // A4 e afișat doar când diferă de standard — altfel
                    // încărcăm degeaba ecranul.
                    if (session.hasCustomA4) ...[
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _green.withAlpha(36),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _green.withAlpha(80)),
                        ),
                        child: Text(
                          'A4 ${session.a4.toStringAsFixed(0)} Hz',
                          style: const TextStyle(
                            color: _green,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${session.stringsTuned}/${session.totalStrings} corzi · '
                  '${session.durationSeconds.toStringAsFixed(0)} s · '
                  '${_formatDate(session.createdAt)}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _instrumentLabel(String id) {
    switch (id) {
      case 'guitar':
        return 'Chitară';
      case 'bass':
        return 'Chitară bass';
      case 'violin':
        return 'Vioară';
      case 'ukulele':
        return 'Ukulele';
      case 'mandolin':
        return 'Mandolină';
      default:
        return id;
    }
  }
}

/// Grafic în bare: numărul de sesiuni pe ultimele 7 zile (ziua de azi
/// pe poziția cea mai din dreapta). Citește local din lista de sesiuni
/// — fără request suplimentar la backend.
class _SevenDayChart extends StatelessWidget {
  const _SevenDayChart({required this.sessions});

  final List<TuningSession> sessions;

  // Ru. zile săptămână din `DateTime.weekday` (1=Luni .. 7=Duminică).
  static const _dayLabels = ['Lu', 'Ma', 'Mi', 'Jo', 'Vi', 'Sâ', 'Du'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // counts[6] = azi, counts[0] = acum 6 zile.
    final counts = List<int>.filled(7, 0);
    for (final s in sessions) {
      final d = DateTime(s.createdAt.year, s.createdAt.month, s.createdAt.day);
      final diff = today.difference(d).inDays;
      if (diff >= 0 && diff < 7) counts[6 - diff]++;
    }
    final peak = max(1, counts.fold<int>(0, (a, b) => a > b ? a : b));
    final totalWeek = counts.fold<int>(0, (a, b) => a + b);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0x10FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _track),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calendar_view_week_rounded,
                color: _green,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'Activitate · 7 zile',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                totalWeek == 0
                    ? 'nicio sesiune'
                    : '$totalWeek ${totalWeek == 1 ? 'sesiune' : 'sesiuni'}',
                style: const TextStyle(color: Colors.white54, fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Înălțime totală = label cifră (14) + spacing (3) + bara max (52)
          // + un padding mic (2) = 71. Margine de 20px ca să nu apară
          // „BOTTOM OVERFLOWED" la bare mari + cifre.
          SizedBox(
            height: 80,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final c = counts[i];
                final h = 6.0 + 52.0 * (c / peak);
                final isToday = i == 6;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Cifra (count) deasupra barei — sare în ochi.
                      SizedBox(
                        height: 14,
                        child: c > 0
                            ? Text(
                                '$c',
                                style: TextStyle(
                                  color: isToday ? _green : Colors.white60,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 3),
                      // Bara propriu-zisă, animată — feedback când chart-ul
                      // se reîmprospătează după o sesiune nouă.
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        height: h,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: c == 0
                                ? const [Color(0x22FFFFFF), Color(0x14FFFFFF)]
                                : [
                                    _green.withAlpha(isToday ? 230 : 170),
                                    _green.withAlpha(isToday ? 110 : 70),
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
          // Etichete zile — azi cu evidențiere.
          Row(
            children: List.generate(7, (i) {
              final date = today.subtract(Duration(days: 6 - i));
              final isToday = i == 6;
              final label = isToday ? 'azi' : _dayLabels[date.weekday - 1];
              return Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isToday ? _green : Colors.white54,
                      fontSize: 11,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
