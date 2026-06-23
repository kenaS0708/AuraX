import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_state.dart';
import 'local_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterDownloader.initialize(debug: false);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const LumenApp(),
    ),
  );
}

// ─── Дизайн-токены ───────────────────────────────────────────

class LC {
  // Light
  static const bgL       = Color(0xFFFAF6F1);
  static const surfL     = Color(0xFFFFFFFF);
  static const surfAltL  = Color(0xFFF2ECE2);
  static const surfSunkL = Color(0xFFEDE5D7);
  static const textL     = Color(0xFF1F1A14);
  static const mutedL    = Color(0xFF6B5F4E);
  static const faintL    = Color(0xFFA89A84);
  static const accentL   = Color(0xFFE8763A);
  static const accentSfL = Color(0xFFF4B584);
  static const accentBgL = Color(0xFFFCE9D8);
  static const accentInkL= Color(0xFF5C2D0C);
  static const successL  = Color(0xFF4A8B5A);
  static const dangerL   = Color(0xFFC4432A);

  // Dark
  static const bgD       = Color(0xFF14110D);
  static const surfD     = Color(0xFF1F1B15);
  static const surfAltD  = Color(0xFF2A241C);
  static const surfSunkD = Color(0xFF0E0C08);
  static const textD     = Color(0xFFF5EFE4);
  static const mutedD    = Color(0xFFB8AC99);
  static const faintD    = Color(0xFF7A7063);
  static const accentD   = Color(0xFFF39158);
  static const accentSfD = Color(0xFFE8763A);
  static const accentBgD = Color(0xFF3B2214);
  static const accentInkD= Color(0xFFFCE9D8);
  static const successD  = Color(0xFF6FB47F);
  static const dangerD   = Color(0xFFE56A4E);
}

class LumenColors {
  final Color bg, surface, surfaceAlt, surfaceSunken;
  final Color text, muted, faint;
  final Color accent, accentSoft, accentBg, accentInk;
  final Color success, danger;
  final bool dark;

  const LumenColors({
    required this.bg, required this.surface, required this.surfaceAlt,
    required this.surfaceSunken, required this.text, required this.muted,
    required this.faint, required this.accent, required this.accentSoft,
    required this.accentBg, required this.accentInk, required this.success,
    required this.danger, required this.dark,
  });

  static const light = LumenColors(
    bg: LC.bgL, surface: LC.surfL, surfaceAlt: LC.surfAltL, surfaceSunken: LC.surfSunkL,
    text: LC.textL, muted: LC.mutedL, faint: LC.faintL,
    accent: LC.accentL, accentSoft: LC.accentSfL, accentBg: LC.accentBgL, accentInk: LC.accentInkL,
    success: LC.successL, danger: LC.dangerL, dark: false,
  );

  static const night = LumenColors(
    bg: LC.bgD, surface: LC.surfD, surfaceAlt: LC.surfAltD, surfaceSunken: LC.surfSunkD,
    text: LC.textD, muted: LC.mutedD, faint: LC.faintD,
    accent: LC.accentD, accentSoft: LC.accentSfD, accentBg: LC.accentBgD, accentInk: LC.accentInkD,
    success: LC.successD, danger: LC.dangerD, dark: true,
  );
}

// ─── Экраны (навигация) ──────────────────────────────────────

enum LScreen { welcome, onboard, download, home, result }

// ─── Главное приложение ──────────────────────────────────────

class LumenApp extends StatelessWidget {
  const LumenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumen',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        fontFamily: 'SF Pro Text',
        scaffoldBackgroundColor: LC.bgL,
      ),
      home: const LumenRoot(),
    );
  }
}

class LumenRoot extends StatefulWidget {
  const LumenRoot({super.key});
  @override
  State<LumenRoot> createState() => _LumenRootState();
}

class _LumenRootState extends State<LumenRoot> {
  LScreen _screen = LScreen.welcome;
  bool _darkMode = false;
  String _layout = 'B';
  bool _onboardingDone = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final done   = p.getBool('lumen_onboarding_done') ?? false;
    final dark   = p.getBool('lumen_dark') ?? false;
    final layout = p.getString('lumen_layout') ?? 'B';

    setState(() {
      _onboardingDone = done;
      _darkMode       = dark;
      _layout         = layout;
      _screen = done ? LScreen.home : LScreen.welcome;
    });
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('lumen_dark', _darkMode);
    await p.setString('lumen_layout', _layout);
  }

  void _go(LScreen s) => setState(() => _screen = s);

  void _finishOnboarding() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('lumen_onboarding_done', true);
    _go(LScreen.home);
  }

  LumenColors get c => _darkMode ? LumenColors.night : LumenColors.light;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
      child: KeyedSubtree(
        key: ValueKey(_screen),
        child: _buildScreen(),
      ),
    );
  }

  Widget _buildScreen() {
    switch (_screen) {
      case LScreen.welcome:
        return WelcomeScreen(c: c, onStart: () => _go(LScreen.onboard));
      case LScreen.onboard:
        return OnboardingScreen(c: c, onDone: _finishOnboarding);
      case LScreen.download:
        return DownloadModelScreen(
          c: c,
          onDone: () => _go(LScreen.home),
        );
      case LScreen.home:
        return HomeScreen(
          c: c,
          layout: _layout,
          darkMode: _darkMode,
          onToggleDark: () {
            setState(() => _darkMode = !_darkMode);
            _savePrefs();
          },
          onLayoutChange: (l) {
            setState(() => _layout = l);
            _savePrefs();
          },
          onResult: () => _go(LScreen.result),
        );
      case LScreen.result:
        return ResultScreen(
          c: c,
          onBack: () => _go(LScreen.home),
          onRetake: () => _go(LScreen.home),
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Shared Widgets
// ─────────────────────────────────────────────────────────────

class LButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final LumenColors c;
  final bool secondary;
  final Widget? icon;
  const LButton({super.key, required this.label, required this.c,
    this.onTap, this.secondary = false, this.icon});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 56,
        decoration: BoxDecoration(
          color: secondary ? Colors.transparent : c.accent,
          borderRadius: BorderRadius.circular(18),
          boxShadow: secondary ? null : [
            BoxShadow(color: c.accent.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 10)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: 8)],
            Text(label, style: TextStyle(
              color: secondary ? c.muted : Colors.white,
              fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2,
            )),
          ],
        ),
      ),
    );
  }
}

class LChip extends StatelessWidget {
  final String label;
  final LumenColors c;
  const LChip({super.key, required this.label, required this.c});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: c.accentBg, borderRadius: BorderRadius.circular(999)),
    child: Text(label, style: TextStyle(color: c.accentInk, fontSize: 13, fontWeight: FontWeight.w600)),
  );
}

class LCard extends StatelessWidget {
  final Widget child;
  final LumenColors c;
  final EdgeInsetsGeometry? padding;
  final double? radius;
  const LCard({super.key, required this.child, required this.c, this.padding, this.radius});

  @override
  Widget build(BuildContext context) => Container(
    padding: padding ?? const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(radius ?? 20),
      boxShadow: [BoxShadow(color: c.dark ? Colors.black38 : const Color(0x101F1A14), blurRadius: 16, offset: const Offset(0, 4))],
    ),
    child: child,
  );
}

// Пульсирующий круг (анимация)
class PulseCircle extends StatefulWidget {
  final Color color;
  final double size;
  const PulseCircle({super.key, required this.color, required this.size});
  @override
  State<PulseCircle> createState() => _PulseCircleState();
}
class _PulseCircleState extends State<PulseCircle> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))..repeat();
    _anim = Tween(begin: 1.0, end: 1.4).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Container(
      width: widget.size * _anim.value,
      height: widget.size * _anim.value,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: widget.color.withOpacity(1 - (_anim.value - 1) / 0.4), width: 2),
      ),
    ),
  );
}

// Радар-волны (Bluetooth поиск)
class RadarWave extends StatefulWidget {
  final Color color;
  final double size;
  final int delay;
  const RadarWave({super.key, required this.color, required this.size, required this.delay});
  @override
  State<RadarWave> createState() => _RadarWaveState();
}
class _RadarWaveState extends State<RadarWave> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat();
    _scale   = Tween(begin: 0.3, end: 1.0).animate(_ctrl);
    _opacity = Tween(begin: 0.7, end: 0.0).animate(_ctrl);
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.forward(from: 0);
    });
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => Opacity(
      opacity: _opacity.value.clamp(0, 1),
      child: Transform.scale(scale: _scale.value, child: Container(
        width: widget.size, height: widget.size,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: widget.color, width: 1.5)),
      )),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// 1. Welcome Screen
// ─────────────────────────────────────────────────────────────

class WelcomeScreen extends StatelessWidget {
  final LumenColors c;
  final VoidCallback onStart;
  const WelcomeScreen({super.key, required this.c, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(children: [
        // Декоративные пятна
        Positioned(top: -80, right: -60, child: Container(
          width: 260, height: 260,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.accentBg),
        ).blurCircle()),
        Positioned(bottom: 180, left: -80, child: Container(
          width: 220, height: 220,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.accentSoft.withOpacity(0.35)),
        ).blurCircle()),

        SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Лого
            Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: c.accent, borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: c.accent.withOpacity(0.33), blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Text('Lumen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.text, letterSpacing: -0.2)),
            ]),

            // Визуал — очки с пульсацией
            Expanded(child: Center(child: Stack(alignment: Alignment.center, children: [
              Container(width: 280, height: 280, decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [c.accentBg, c.bg.withOpacity(0)]),
              )),
              PulseCircle(color: c.accent, size: 240),
              Container(
                width: 220, height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: c.surface,
                  boxShadow: [BoxShadow(color: c.dark ? Colors.black38 : const Color(0x181F1A14), blurRadius: 32, offset: const Offset(0, 12))],
                ),
                child: Icon(Icons.remove_red_eye_outlined, size: 90, color: c.accent),
              ),
            ]))),

            // Текст
            Text('Ваши глаза —\nтеперь и умные',
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: c.text, height: 1.1, letterSpacing: -0.8)),
            const SizedBox(height: 16),
            Text('Помощник для очков с ИИ. Работает онлайн для точных ответов и офлайн, когда связи нет.',
              style: TextStyle(fontSize: 17, color: c.muted, height: 1.45, letterSpacing: -0.2)),
            const SizedBox(height: 32),

            LButton(label: 'Начать', c: c, onTap: onStart),
            const SizedBox(height: 12),
            LButton(label: 'У меня уже есть аккаунт', c: c, secondary: true),
          ]),
        )),
      ]),
    );
  }
}

extension _BlurExt on Widget {
  Widget blurCircle() => this; // упрощение без ImageFilter в Scaffold
}

// ─────────────────────────────────────────────────────────────
// 2. Onboarding Screen
// ─────────────────────────────────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  final LumenColors c;
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.c, required this.onDone});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  LumenColors get c => widget.c;

  final _steps = const [
    (icon: Icons.remove_red_eye_outlined, title: 'Что умеют очки',
     body: 'Читают текст, описывают сцену, распознают лица и предупреждают о препятствиях — всё голосом в наушник.'),
    (icon: Icons.shield_outlined, title: 'Приватность прежде всего',
     body: 'Модель ИИ работает прямо на вашем телефоне. Снимки не уходят в облако без вашего разрешения.'),
    (icon: Icons.check_circle_outline_rounded, title: 'Ваше согласие',
     body: 'Включая приложение, вы разрешаете обработку изображения и звука с очков. Вы можете остановить это в любой момент.'),
  ];

  @override
  Widget build(BuildContext context) {
    final cur = _steps[_step];
    final last = _step == _steps.length - 1;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Прогресс + пропустить
          Row(children: [
            ...List.generate(_steps.length, (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: i == _step ? 24 : 8, height: 8,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: i == _step ? c.accent : c.surfaceSunken,
                borderRadius: BorderRadius.circular(4),
              ),
            )),
            const Spacer(),
            GestureDetector(
              onTap: widget.onDone,
              child: Text('Пропустить', style: TextStyle(color: c.muted, fontSize: 16, fontWeight: FontWeight.w500)),
            ),
          ]),

          // Иконка
          Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Container(
                key: ValueKey(_step),
                width: 140, height: 140,
                decoration: BoxDecoration(color: c.accentBg, borderRadius: BorderRadius.circular(40),
                  boxShadow: [BoxShadow(color: c.dark ? Colors.black26 : const Color(0x101F1A14), blurRadius: 24, offset: const Offset(0, 8))]),
                child: Icon(cur.icon, size: 64, color: c.accent),
              ),
            ),
            const SizedBox(height: 36),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Column(key: ValueKey(_step), children: [
                Text(cur.title, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: c.text, letterSpacing: -0.5)),
                const SizedBox(height: 14),
                Text(cur.body, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: c.muted, height: 1.5, letterSpacing: -0.1)),
              ]),
            ),
          ]))),

          LButton(
            label: last ? 'Согласен и продолжить' : 'Далее',
            c: c,
            onTap: () => last ? widget.onDone() : setState(() => _step++),
          ),
        ]),
      )),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 3. Download Model Screen
// ─────────────────────────────────────────────────────────────

class DownloadModelScreen extends StatefulWidget {
  final LumenColors c;
  final VoidCallback onDone;
  const DownloadModelScreen({super.key, required this.c, required this.onDone});
  @override
  State<DownloadModelScreen> createState() => _DownloadModelScreenState();
}

class _DownloadModelScreenState extends State<DownloadModelScreen> {
  bool _whyOpen = false;
  LumenColors get c => widget.c;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppState>().localModel;
    final status = model.status;
    final progress = model.progress;

    final isDone = status == ModelStatus.ready;
    final isFailed = status == ModelStatus.failed;
    final isLoading = status == ModelStatus.loading;
    final isDownloading = status == ModelStatus.downloadingModel || status == ModelStatus.downloadingMmproj;
    final notStarted = status == ModelStatus.notDownloaded;

    final pct = (progress * 100).round();

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Большой круговой прогресс
          Center(child: SizedBox(width: 200, height: 200, child: Stack(alignment: Alignment.center, children: [
            CustomPaint(
              size: const Size(200, 200),
              painter: _CircleProgressPainter(
                progress: progress,
                trackColor: c.surfaceAlt,
                fillColor: isDone ? c.success : isFailed ? c.danger : c.accent,
              ),
            ),
            if (isDone)
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(shape: BoxShape.circle, color: c.success,
                  boxShadow: [BoxShadow(color: c.success.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 8))]),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 44),
              )
            else if (isFailed)
              Icon(Icons.error_outline_rounded, size: 56, color: c.danger)
            else if (isLoading)
              Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 32, height: 32, child: CircularProgressIndicator(color: c.accent, strokeWidth: 3)),
                const SizedBox(height: 8),
                Text('Загрузка...', style: TextStyle(fontSize: 12, color: c.muted)),
              ])
            else
              Column(mainAxisSize: MainAxisSize.min, children: [
                RichText(text: TextSpan(children: [
                  TextSpan(text: '$pct', style: TextStyle(fontSize: 48, fontWeight: FontWeight.w700, color: c.text, letterSpacing: -1)),
                  TextSpan(text: '%', style: TextStyle(fontSize: 24, color: c.muted)),
                ])),
                const SizedBox(height: 2),
                Text(
                  status == ModelStatus.downloadingMmproj ? 'Vision (~1 GB)' : '~3.1 GB',
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              ]),
          ]))),

          const SizedBox(height: 24),
          Text(
            isDone ? 'Всё готово' : 'Готовим офлайн-модель',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: c.text, letterSpacing: -0.5),
          ),
          const SizedBox(height: 8),
          Text(
            isFailed && model.errorMessage != null
                ? model.errorMessage!
                : 'Скачиваем локальный ИИ, чтобы приложение работало даже без интернета — на улице, в метро, в дороге.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: isFailed ? c.danger : c.muted, height: 1.4),
          ),
          const SizedBox(height: 24),

          // Карточка со шагами
          LCard(c: c, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 40, height: 40, decoration: BoxDecoration(color: c.accentBg, borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.download_rounded, color: c.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Gemma 4 E2B · Q4_K_M', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                Text('Gemma 4 Vision · локальная', style: TextStyle(fontSize: 12, color: c.muted)),
              ])),
            ]),
            Divider(color: c.surfaceAlt, height: 24),
            ..._buildSteps(status),
          ])),

          const SizedBox(height: 12),

          // Почему это нужно
          GestureDetector(
            onTap: () => setState(() => _whyOpen = !_whyOpen),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: c.accentBg, borderRadius: BorderRadius.circular(20)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.shield_outlined, color: c.accent, size: 22),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Почему это нужно?',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.accentInk))),
                  AnimatedRotation(
                    turns: _whyOpen ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.chevron_right_rounded, color: c.accent),
                  ),
                ]),
                if (_whyOpen) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(left: 34),
                    child: Text(
                      'Когда есть интернет — запросы идут на мощный серверный ИИ (ответы точнее и быстрее). Когда сети нет — кадры обрабатываются прямо на телефоне. Переключение автоматическое.',
                      style: TextStyle(fontSize: 14, color: c.accentInk.withOpacity(0.85), height: 1.45),
                    ),
                  ),
                ],
              ]),
            ),
          ),

          const Spacer(),

          if (notStarted || isFailed)
            LButton(
              label: isFailed ? 'Попробовать снова' : 'Скачать модель',
              c: c,
              onTap: () => isFailed
                  ? context.read<AppState>().localModel.retryDownload()
                  : context.read<AppState>().localModel.startDownload(),
            )
          else
            LButton(
              label: isDone ? 'Продолжить' : '$pct%',
              c: c,
              onTap: isDone ? widget.onDone : null,
            ),

          const SizedBox(height: 8),
          if (!isDone && !notStarted)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              TextButton(
                onPressed: widget.onDone,
                child: Text('Пропустить', style: TextStyle(color: c.muted, fontSize: 14)),
              ),
              Text('·', style: TextStyle(color: c.faint)),
              TextButton(
                onPressed: () => context.read<AppState>().localModel.deleteAndRedownload(),
                child: Text('Скачать заново', style: TextStyle(color: c.danger, fontSize: 14)),
              ),
            ]),
        ]),
      )),
    );
  }

  List<Widget> _buildSteps(ModelStatus status) {
    final steps = [
      ('Скачивание Gemma 4', ModelStatus.downloadingModel),
      ('Скачивание Vision-проектора', ModelStatus.downloadingMmproj),
      ('Инициализация', ModelStatus.loading),
    ];
    return steps.asMap().entries.map((e) {
      final i = e.key;
      final s = e.value;
      final isDone = _isStepDone(status, i);
      final isActive = status == s.$2;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 22, height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone ? widget.c.success : isActive ? widget.c.accent : widget.c.surfaceSunken,
            ),
            child: isDone
                ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                : isActive
                    ? Center(child: _BlinkDot(color: Colors.white))
                    : Center(child: Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.c.faint))),
          ),
          const SizedBox(width: 12),
          Text(s.$1,
            style: TextStyle(
              fontSize: 15,
              color: (isActive || isDone) ? widget.c.text : widget.c.muted,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            )),
        ]),
      );
    }).toList();
  }

  bool _isStepDone(ModelStatus status, int stepIndex) {
    const order = [ModelStatus.downloadingModel, ModelStatus.downloadingMmproj, ModelStatus.loading, ModelStatus.ready];
    final cur = order.indexOf(status);
    return cur > stepIndex;
  }
}

class _BlinkDot extends StatefulWidget {
  final Color color;
  const _BlinkDot({required this.color});
  @override
  State<_BlinkDot> createState() => _BlinkDotState();
}
class _BlinkDotState extends State<_BlinkDot> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.3, end: 1.0).animate(_c),
    child: Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
  );
}

class _CircleProgressPainter extends CustomPainter {
  final double progress;
  final Color trackColor, fillColor;
  const _CircleProgressPainter({required this.progress, required this.trackColor, required this.fillColor});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2, r = size.width / 2 - 10;
    final track = Paint()..color = trackColor..style = PaintingStyle.stroke..strokeWidth = 10..strokeCap = StrokeCap.round;
    final fill = Paint()..color = fillColor..style = PaintingStyle.stroke..strokeWidth = 10..strokeCap = StrokeCap.round;
    canvas.drawCircle(Offset(cx, cy), r, track);
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r),
      -pi / 2, 2 * pi * progress.clamp(0, 1), false, fill);
  }

  @override
  bool shouldRepaint(covariant _CircleProgressPainter old) => old.progress != progress || old.fillColor != fillColor;
}

// ─────────────────────────────────────────────────────────────
// 4. Home Screen
// ─────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  final LumenColors c;
  final String layout;
  final bool darkMode;
  final VoidCallback onToggleDark;
  final ValueChanged<String> onLayoutChange;
  final VoidCallback onResult;

  const HomeScreen({
    super.key, required this.c, required this.layout,
    required this.darkMode, required this.onToggleDark,
    required this.onLayoutChange, required this.onResult,
  });
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _showSettings = false;
  bool _capturing = false;

  LumenColors get c => widget.c;

  void _capture(BuildContext ctx) async {
    setState(() => _capturing = true);
    ctx.read<AppState>().onCaptureButtonClick();
    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted) {
      setState(() => _capturing = false);
      widget.onResult();
    }
  }

  void _captureFromGallery(BuildContext ctx) async {
    final picked = await ctx.read<AppState>().analyzeGalleryPhoto();
    if (!picked || !mounted) return;
    setState(() => _capturing = true);
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) {
      setState(() => _capturing = false);
      widget.onResult();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (_capturing) {
      return _CapturingScreen(c: c, online: state.isServerOnline);
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(children: [
        SafeArea(child: Column(children: [
          _HomeHeader(c: c, state: state, onSettings: () => setState(() => _showSettings = true)),
          _YoloBanner(c: c, yolo: state.yoloModel),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: _buildLayout(context, state),
          )),
        ])),

        if (_showSettings)
          _SettingsOverlay(
            c: c,
            state: state,
            darkMode: widget.darkMode,
            layout: widget.layout,
            onToggleDark: widget.onToggleDark,
            onLayoutChange: widget.onLayoutChange,
            onDismiss: () => setState(() => _showSettings = false),
          ),
      ]),
    );
  }

  Widget _buildLayout(BuildContext ctx, AppState state) {
    switch (widget.layout) {
      case 'A': return _HomeLayoutA(c: c, onCapture: () => _capture(ctx), onGallery: () => _captureFromGallery(ctx));
      case 'B': return _HomeLayoutB(c: c, onCapture: () => _capture(ctx), onGallery: () => _captureFromGallery(ctx));
      case 'C': return _HomeLayoutC(c: c, onCapture: () => _capture(ctx), onGallery: () => _captureFromGallery(ctx));
      default:  return _HomeLayoutB(c: c, onCapture: () => _capture(ctx), onGallery: () => _captureFromGallery(ctx));
    }
  }
}

class _YoloBanner extends StatelessWidget {
  final LumenColors c;
  final dynamic yolo; // YoloModelManager
  const _YoloBanner({required this.c, required this.yolo});

  @override
  Widget build(BuildContext context) {
    final status   = yolo.status;
    final isReady  = yolo.isReady;
    final isDown   = status.toString().contains('downloading');
    final isLoad   = status.toString().contains('loading');
    final isFailed = status.toString().contains('failed');
    final isNone   = status.toString().contains('notDownloaded');

    if (isReady) return const SizedBox.shrink();

    final Color fg  = isFailed ? c.danger : c.accent;
    final Color bg  = isFailed ? c.danger.withOpacity(0.12) : c.accentBg;
    final Color ink = isFailed ? c.danger : c.accentInk;

    final String label = isFailed
        ? (yolo.error?.toString().split('\n').first ?? 'Ошибка инициализации')
        : 'Инициализация офлайн-детектора…';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: fg.withOpacity(0.25)),
      ),
      child: Row(children: [
        if (isDown || isLoad)
          SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(color: fg, strokeWidth: 2.5))
        else
          Icon(isFailed ? Icons.error_outline_rounded : Icons.offline_bolt_rounded,
              color: fg, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Офлайн ИИ (YOLO)', style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: fg, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, color: ink),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          if (isDown) ...[
            const SizedBox(height: 6),
            ClipRRect(borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: yolo.progress, backgroundColor: fg.withOpacity(0.15),
                color: fg, minHeight: 3)),
          ],
        ])),
        if (isFailed) ...[
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => context.read<AppState>().yoloModel.downloadAndLoad(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                  color: fg, borderRadius: BorderRadius.circular(10)),
              child: const Text('Повторить',
                  style: TextStyle(color: Colors.white,
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ]),
    );
  }
}

class _ModelBanner extends StatelessWidget {
  final LumenColors c;
  final LocalModelManager model;
  const _ModelBanner({required this.c, required this.model});

  @override
  Widget build(BuildContext context) {
    final status = model.status;
    final isError   = status == ModelStatus.failed;
    final isLoading = status == ModelStatus.loading;
    final isDl      = status == ModelStatus.downloadingModel || status == ModelStatus.downloadingMmproj;
    final isNone    = status == ModelStatus.notDownloaded;

    final Color bg  = isError ? c.danger.withOpacity(0.12) : c.accentBg;
    final Color fg  = isError ? c.danger : c.accent;
    final Color ink = isError ? c.danger : c.accentInk;

    final String label = isError
        ? (model.errorMessage != null
            ? 'Ошибка: ${model.errorMessage!.substring(0, model.errorMessage!.length.clamp(0, 60))}'
            : 'Ошибка загрузки модели')
        : isLoading ? 'Загружаем модель в память…'
        : isDl ? 'Скачивание ${status == ModelStatus.downloadingMmproj ? "vision" : "модели"}… ${(model.progress * 100).round()}%'
        : 'Локальная модель не скачана';

    final String btnLabel = isError ? 'Попробовать снова'
        : isDl ? '' : isLoading ? '' : 'Скачать';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: fg.withOpacity(0.25)),
      ),
      child: Row(children: [
        // Иконка / индикатор
        if (isDl || isLoading)
          SizedBox(width: 20, height: 20,
            child: CircularProgressIndicator(color: fg, strokeWidth: 2.5))
        else
          Icon(isError ? Icons.error_outline_rounded : Icons.memory_rounded, color: fg, size: 20),
        const SizedBox(width: 12),

        // Текст
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Локальный ИИ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: fg, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, color: ink),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          if (isDl) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: model.progress,
                backgroundColor: fg.withOpacity(0.15),
                color: fg, minHeight: 3,
              ),
            ),
          ],
        ])),

        // Кнопка действия
        if (btnLabel.isNotEmpty) ...[
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => isError
                ? context.read<AppState>().localModel.retryDownload()
                : context.read<AppState>().localModel.startDownload(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: fg, borderRadius: BorderRadius.circular(10),
              ),
              child: Text(btnLabel, style: const TextStyle(color: Colors.white,
                  fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ]),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  final LumenColors c;
  final AppState state;
  final VoidCallback onSettings;
  const _HomeHeader({required this.c, required this.state, required this.onSettings});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      child: Row(children: [
        // Аватар
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [c.accent, c.accentSoft]),
          ),
          child: const Center(child: Text('М', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17))),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Привет, Мария', style: TextStyle(fontSize: 13, color: c.muted, letterSpacing: -0.1)),
          const SizedBox(height: 2),
          Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: state.isBleConnected ? c.success : c.faint,
              boxShadow: state.isBleConnected ? [BoxShadow(color: c.success.withOpacity(0.35), blurRadius: 6, spreadRadius: 1)] : null,
            )),
            const SizedBox(width: 6),
            Flexible(child: Text(
              state.isBleConnected ? 'Очки на связи · 92%' : state.statusText,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text),
              overflow: TextOverflow.ellipsis,
            )),
          ]),
        ])),
        // Online/Offline пилюля
        _ModePill(c: c, online: state.isServerOnline),
        const SizedBox(width: 8),
        // Настройки
        GestureDetector(
          onTap: onSettings,
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
            child: Icon(Icons.tune_rounded, size: 18, color: c.muted),
          ),
        ),
      ]),
    );
  }
}

class _ModePill extends StatelessWidget {
  final LumenColors c;
  final bool online;
  const _ModePill({required this.c, required this.online});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: online ? c.accent : c.surfaceAlt,
      borderRadius: BorderRadius.circular(999),
      boxShadow: online ? [BoxShadow(color: c.accent.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4))] : null,
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(online ? Icons.cloud_rounded : Icons.phone_android_rounded,
        size: 14, color: online ? Colors.white : c.text),
      const SizedBox(width: 5),
      Text(online ? 'Cloud AI' : 'On-device',
        style: TextStyle(color: online ? Colors.white : c.text, fontSize: 12, fontWeight: FontWeight.w700)),
    ]),
  );
}

// Live feed с очков (имитация)
class _GlassesLiveFeed extends StatelessWidget {
  final LumenColors c;
  final double height;
  const _GlassesLiveFeed({required this.c, this.height = 200});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF2a3540), Color(0xFF404b56)]),
        boxShadow: [BoxShadow(color: c.dark ? Colors.black38 : const Color(0x181F1A14), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(children: [
        // Виньетка
        Positioned.fill(child: CustomPaint(painter: _VignettePainter(c.accent))),
        // Рамка фокуса
        Center(child: SizedBox(width: 88, height: 88, child: CustomPaint(painter: _FocusBracketPainter()))),
        // LIVE
        Positioned(top: 14, left: 14, child: _GlassBadge(child: Row(children: [
          Container(width: 7, height: 7, margin: const EdgeInsets.only(right: 6),
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFF4A4A))),
          const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
        ]))),
        // Лейбл очков
        Positioned(top: 14, right: 14, child: _GlassBadge(child: Row(children: [
          const Icon(Icons.remove_red_eye_outlined, color: Colors.white, size: 14),
          const SizedBox(width: 5),
          const Text('Lumen Frames', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        ]))),
      ]),
    );
  }
}

class _GlassBadge extends StatelessWidget {
  final Widget child;
  const _GlassBadge({required this.child});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(999),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      color: Colors.black.withOpacity(0.45),
      child: child,
    ),
  );
}

class _VignettePainter extends CustomPainter {
  final Color accent;
  const _VignettePainter(this.accent);
  @override
  void paint(Canvas canvas, Size size) {
    final r = RadialGradient(center: const Alignment(-0.4, -0.2), radius: 0.6,
      colors: [accent.withOpacity(0.25), Colors.transparent]).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..shader = r);
  }
  @override bool shouldRepaint(_) => false;
}

class _FocusBracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white..strokeWidth = 2..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    const l = 18.0;
    // Углы
    for (final c in [Offset.zero, Offset(size.width, 0), Offset(0, size.height), Offset(size.width, size.height)]) {
      final dx = c.dx == 0 ? 1.0 : -1.0;
      final dy = c.dy == 0 ? 1.0 : -1.0;
      canvas.drawLine(c, c + Offset(l * dx, 0), p);
      canvas.drawLine(c, c + Offset(0, l * dy), p);
    }
  }
  @override bool shouldRepaint(_) => false;
}

// Layout A — большая круглая кнопка
class _HomeLayoutA extends StatelessWidget {
  final LumenColors c;
  final VoidCallback onCapture;
  final VoidCallback onGallery;
  const _HomeLayoutA({required this.c, required this.onCapture, required this.onGallery});

  @override
  Widget build(BuildContext context) {
    final modes = [
      (label: 'Читать текст', icon: Icons.menu_book_rounded),
      (label: 'Описать сцену', icon: Icons.remove_red_eye_outlined),
      (label: 'Узнать лицо', icon: Icons.face_rounded),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _GlassesLiveFeed(c: c),
        const SizedBox(height: 20),
        Text('Быстрые режимы', style: TextStyle(fontSize: 13, color: c.muted, fontWeight: FontWeight.w600, letterSpacing: 1)),
        const SizedBox(height: 10),
        Row(children: modes.map((m) => Expanded(child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: onCapture,
            child: LCard(c: c, padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10), child: Column(children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: c.accentBg, borderRadius: BorderRadius.circular(12)),
                child: Icon(m.icon, color: c.accent, size: 22)),
              const SizedBox(height: 8),
              Text(m.label, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.text, height: 1.2)),
            ])),
          ),
        ))).toList()),
        const SizedBox(height: 24),
        Center(child: Column(children: [
          GestureDetector(
            onTap: onCapture,
            child: Stack(alignment: Alignment.center, children: [
              Container(width: 108, height: 108, decoration: BoxDecoration(
                shape: BoxShape.circle, border: Border.all(color: c.accent.withOpacity(0.3), width: 3))),
              Container(width: 96, height: 96, decoration: BoxDecoration(
                shape: BoxShape.circle, color: c.accent,
                boxShadow: [BoxShadow(color: c.accent.withOpacity(0.35), blurRadius: 40, spreadRadius: 4, offset: const Offset(0, 15))],
              ), child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 40)),
            ]),
          ),
          const SizedBox(height: 10),
          Text('Нажмите и удерживайте для серии', style: TextStyle(fontSize: 13, color: c.muted)),
        ])),
        const SizedBox(height: 16),
        _GalleryButton(c: c, onTap: onGallery),
      ]),
    );
  }
}

// Layout B — 6 крупных плиток + широкая pill-кнопка
class _HomeLayoutB extends StatelessWidget {
  final LumenColors c;
  final VoidCallback onCapture;
  final VoidCallback onGallery;
  const _HomeLayoutB({required this.c, required this.onCapture, required this.onGallery});

  @override
  Widget build(BuildContext context) {
    final modes = [
      (label: 'Читать текст',    icon: Icons.menu_book_rounded,     tint: LC.accentBgL, danger: false),
      (label: 'Описать сцену',   icon: Icons.remove_red_eye_outlined, tint: const Color(0xFFE4EFDA), danger: false),
      (label: 'Узнать лицо',     icon: Icons.face_rounded,           tint: const Color(0xFFE3E8F5), danger: false),
      (label: 'Найти предмет',   icon: Icons.search_rounded,         tint: const Color(0xFFF5E2E4), danger: false),
      (label: 'Препятствия',     icon: Icons.warning_amber_rounded,  tint: const Color(0xFFFCEFD2), danger: false),
      (label: 'Экстренный вызов',icon: Icons.sos_rounded,            tint: const Color(0xFFF9D8D2), danger: true),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Быстрые режимы', style: TextStyle(fontSize: 13, color: c.muted, fontWeight: FontWeight.w600, letterSpacing: 1)),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2, childAspectRatio: 1.55, crossAxisSpacing: 10, mainAxisSpacing: 10,
          children: modes.map((m) => GestureDetector(
            onTap: onCapture,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.dark ? c.surface : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: c.dark ? Colors.black26 : const Color(0x0C1F1A14), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 44, height: 44, decoration: BoxDecoration(
                  color: m.danger ? const Color(0xFFF9D8D2) : (c.dark ? c.surfaceAlt : m.tint),
                  borderRadius: BorderRadius.circular(14),
                ), child: Icon(m.icon, color: m.danger ? c.danger : c.accent, size: 22)),
                const Spacer(),
                Text(m.label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text, height: 1.2)),
              ]),
            ),
          )).toList(),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: onCapture,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: c.accent, borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: c.accent.withOpacity(0.35), blurRadius: 36, offset: const Offset(0, 15))],
            ),
            child: Row(children: [
              Container(width: 56, height: 56, decoration: BoxDecoration(
                shape: BoxShape.circle, color: Colors.white.withOpacity(0.22)),
                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 28)),
              const SizedBox(width: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Сделать снимок', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                const SizedBox(height: 2),
                Text('Нажмите и удерживайте для серии', style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13)),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        _GalleryButton(c: c, onTap: onGallery),
      ]),
    );
  }
}

// Layout C — история + sticky кнопка
class _HomeLayoutC extends StatelessWidget {
  final LumenColors c;
  final VoidCallback onCapture;
  final VoidCallback onGallery;
  const _HomeLayoutC({required this.c, required this.onCapture, required this.onGallery});

  @override
  Widget build(BuildContext context) {
    final modes = [
      (label: 'Читать текст', icon: Icons.menu_book_rounded),
      (label: 'Описать сцену', icon: Icons.remove_red_eye_outlined),
      (label: 'Узнать лицо', icon: Icons.face_rounded),
      (label: 'Найти предмет', icon: Icons.search_rounded),
    ];
    final history = [
      (time: '9:12', icon: Icons.menu_book_rounded, text: 'Прочитал этикетку: «Оливковое масло Extra Virgin, 500 мл»'),
      (time: '8:47', icon: Icons.remove_red_eye_outlined, text: 'Описал сцену: кухонный стол с кофе и книгой у окна'),
      (time: 'Вчера', icon: Icons.face_rounded, text: 'Узнал: Анна (подруга) и Михаил (муж Анны)'),
      (time: 'Вчера', icon: Icons.search_rounded, text: 'Нашёл ключи: на полке у двери, слева от вазы'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Режимы — горизонтальный скролл
        SizedBox(height: 48, child: ListView(scrollDirection: Axis.horizontal, children: modes.map((m) => Padding(
          padding: const EdgeInsets.only(right: 10),
          child: GestureDetector(
            onTap: onCapture,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: c.dark ? Colors.black26 : const Color(0x0C1F1A14), blurRadius: 8, offset: const Offset(0, 2))]),
              child: Row(children: [Icon(m.icon, color: c.accent, size: 16), const SizedBox(width: 8),
                Text(m.label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text))]),
            ),
          ),
        )).toList())),
        const SizedBox(height: 16),
        Text('Недавние запросы', style: TextStyle(fontSize: 13, color: c.muted, fontWeight: FontWeight.w600, letterSpacing: 1)),
        const SizedBox(height: 10),
        ...history.map((h) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: LCard(c: c, padding: const EdgeInsets.all(14), child: Row(children: [
            Container(width: 36, height: 36, decoration: BoxDecoration(color: c.accentBg, borderRadius: BorderRadius.circular(10)),
              child: Icon(h.icon, color: c.accent, size: 18)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(h.text, style: TextStyle(fontSize: 14, color: c.text, height: 1.35)),
              const SizedBox(height: 4),
              Text(h.time, style: TextStyle(fontSize: 11, color: c.faint)),
            ])),
          ])),
        )),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: onCapture,
          child: Container(
            height: 62, alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.accent, borderRadius: BorderRadius.circular(22),
              boxShadow: [BoxShadow(color: c.accent.withOpacity(0.35), blurRadius: 36, offset: const Offset(0, 15))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              const Text('Сделать снимок', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        _GalleryButton(c: c, onTap: onGallery),
      ]),
    );
  }
}

// ─── Кнопка «Из галереи» (тест без камеры) ───────────────────

class _GalleryButton extends StatelessWidget {
  final LumenColors c;
  final VoidCallback onTap;
  const _GalleryButton({required this.c, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.faint.withOpacity(0.4)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.photo_library_outlined, size: 20, color: c.muted),
        const SizedBox(width: 10),
        Text('Выбрать фото из галереи',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.muted)),
      ]),
    ),
  );
}

// ─── Экран «Снимается» ────────────────────────────────────────

class _CapturingScreen extends StatelessWidget {
  final LumenColors c;
  final bool online;
  const _CapturingScreen({required this.c, required this.online});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 160, height: 160, child: Stack(alignment: Alignment.center, children: [
          RadarWave(color: c.accent, size: 160, delay: 0),
          RadarWave(color: c.accent, size: 160, delay: 800),
          RadarWave(color: c.accent, size: 160, delay: 1600),
          Icon(Icons.auto_awesome_rounded, size: 56, color: c.accent),
        ])),
        const SizedBox(height: 24),
        Text(
          online ? 'Снимок отправлен в облако…' : 'Обработка на телефоне…',
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Text(
          online ? 'Серверная модель даёт самые точные ответы'
            : 'Интернета нет — работает локальная модель.\nВсе данные остаются на телефоне.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14, height: 1.4),
        ),
      ])),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 5. Result Screen
// ─────────────────────────────────────────────────────────────

class ResultScreen extends StatefulWidget {
  final LumenColors c;
  final VoidCallback onBack;
  final VoidCallback onRetake;
  const ResultScreen({super.key, required this.c, required this.onBack, required this.onRetake});
  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  String _typed = '';
  bool _playing = true;
  double _progress = 0;
  String? _shownResponse;

  LumenColors get c => widget.c;

  @override
  void initState() {
    super.initState();
    _animateProgress();
    final initial = context.read<AppState>().aiResponse;
    if (initial != null) _startTypewriter(initial);
  }

  void _startTypewriter(String text) {
    if (_shownResponse == text) return;
    _shownResponse = text;
    _typed = '';
    var i = 0;
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 18));
      if (!mounted) return false;
      if (i < text.length) {
        setState(() => _typed = text.substring(0, ++i));
        return true;
      }
      return false;
    });
  }

  void _animateProgress() async {
    while (mounted && _playing) {
      await Future.delayed(const Duration(milliseconds: 90));
      if (mounted) setState(() => _progress = (_progress + 1.2) % 100);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final online = state.isServerOnline;
    final photo = state.lastPhoto;

    // Start typewriter when AI response arrives (may happen after screen opens)
    final response = state.aiResponse;
    if (response != null && response != _shownResponse) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startTypewriter(response);
      });
    }

    final chips = ['Объект 1', 'Объект 2', 'Объект 3'];

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(child: Column(children: [
        // Хедер
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(children: [
            GestureDetector(
              onTap: widget.onBack,
              child: Container(width: 40, height: 40, decoration: BoxDecoration(
                color: c.surface, borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: c.dark ? Colors.black26 : const Color(0x0C1F1A14), blurRadius: 8)]),
                child: Icon(Icons.chevron_left_rounded, color: c.text)),
            ),
            Expanded(child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Анализ снимка', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: online ? c.accentBg : c.surfaceAlt,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(online ? 'Cloud' : 'On-device',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5,
                    color: online ? c.accentInk : c.muted)),
              ),
            ]))),
            const SizedBox(width: 40),
          ]),
        ),

        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Фото с очков
            Container(
              height: 220,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: c.dark ? Colors.black38 : const Color(0x181F1A14), blurRadius: 16, offset: const Offset(0, 6))]),
              clipBehavior: Clip.hardEdge,
              child: photo != null
                  ? Image.memory(photo, fit: BoxFit.cover)
                  : Container(
                    decoration: const BoxDecoration(gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [Color(0xFF3c2a1c), Color(0xFF5a4530)])),
                    child: const Center(child: Icon(Icons.camera_alt_outlined, color: Colors.white54, size: 48)),
                  ),
            ),
            const SizedBox(height: 16),

            // Чипы объектов
            Text('Обнаружено', style: TextStyle(fontSize: 12, color: c.muted, fontWeight: FontWeight.w600, letterSpacing: 1)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: chips.map((x) => LChip(label: x, c: c)).toList()),
            const SizedBox(height: 16),

            // Карточка озвучивания
            LCard(c: c, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                GestureDetector(
                  onTap: () => setState(() {
                    _playing = !_playing;
                    if (_playing) _animateProgress();
                  }),
                  child: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: c.accent,
                      boxShadow: [BoxShadow(color: c.accent.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 6))]),
                    child: Icon(_playing ? Icons.pause_rounded : Icons.volume_up_rounded, color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_playing ? 'Озвучиваю' : 'Пауза',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: _progress / 100,
                      backgroundColor: c.surfaceSunken,
                      color: c.accent,
                      minHeight: 4,
                    ),
                  ),
                ])),
                const SizedBox(width: 12),
                // Волна-эквалайзер
                SizedBox(height: 24, child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(5, (i) => Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: _WaveBar(color: c.accent, playing: _playing, index: i),
                  )),
                )),
              ]),
              const SizedBox(height: 14),
              // Субтитры
              Text(_typed.isEmpty && _shownResponse == null ? 'Анализируем...' : _typed + (_typed.length < (_shownResponse?.length ?? 0) ? '│' : ''),
                style: TextStyle(fontSize: 17, color: c.text, height: 1.5, letterSpacing: -0.1)),
            ])),
            const SizedBox(height: 14),

            // Действия
            Row(children: [
              Expanded(child: GestureDetector(
                onTap: () {},
                child: LCard(c: c, padding: const EdgeInsets.all(0), child: SizedBox(
                  height: 50,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.volume_up_rounded, size: 18, color: c.text),
                    const SizedBox(width: 8),
                    Text('Прочитать снова', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                  ]),
                )),
              )),
              const SizedBox(width: 10),
              Expanded(child: GestureDetector(
                onTap: widget.onRetake,
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: c.accent, borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: c.accent.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 6))],
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    const Text('Ещё снимок', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  ]),
                ),
              )),
            ]),

            // Галерея фото (если есть)
            if (state.photos.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Все снимки', style: TextStyle(fontSize: 13, color: c.muted, fontWeight: FontWeight.w600, letterSpacing: 1)),
              const SizedBox(height: 10),
              SizedBox(height: 80, child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: state.photos.length,
                itemBuilder: (_, i) {
                  final p = state.photos[state.photos.length - 1 - i];
                  return GestureDetector(
                    onTap: () => _showFullPhoto(context, p),
                    child: Container(
                      width: 80, height: 80, margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
                      clipBehavior: Clip.hardEdge,
                      child: Image.memory(p, fit: BoxFit.cover),
                    ),
                  );
                },
              )),
            ],
          ]),
        )),
      ])),
    );
  }

  void _showFullPhoto(BuildContext context, Uint8List photo) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0),
      body: InteractiveViewer(child: Center(child: Image.memory(photo))),
    )));
  }
}

class _WaveBar extends StatefulWidget {
  final Color color;
  final bool playing;
  final int index;
  const _WaveBar({required this.color, required this.playing, required this.index});
  @override
  State<_WaveBar> createState() => _WaveBarState();
}
class _WaveBarState extends State<_WaveBar> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _h;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: Duration(milliseconds: 600 + widget.index * 100))..repeat(reverse: true);
    _h = Tween(begin: 4.0, end: 12.0 + widget.index * 2).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  void didUpdateWidget(covariant _WaveBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.playing ? _c.repeat(reverse: true) : _c.stop();
  }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _h,
    builder: (_, __) => Container(width: 3, height: widget.playing ? _h.value : 4,
      decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(1.5))),
  );
}

// ─────────────────────────────────────────────────────────────
// 6. Settings Overlay
// ─────────────────────────────────────────────────────────────

class _SettingsOverlay extends StatefulWidget {
  final LumenColors c;
  final AppState state;
  final bool darkMode;
  final String layout;
  final VoidCallback onToggleDark;
  final ValueChanged<String> onLayoutChange;
  final VoidCallback onDismiss;
  const _SettingsOverlay({
    required this.c, required this.state, required this.darkMode,
    required this.layout, required this.onToggleDark,
    required this.onLayoutChange, required this.onDismiss,
  });
  @override
  State<_SettingsOverlay> createState() => _SettingsOverlayState();
}

class _SettingsOverlayState extends State<_SettingsOverlay> {
  late TextEditingController _urlCtrl;
  late TextEditingController _bleCtrl;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.state.serverUrl);
    _bleCtrl = TextEditingController(text: widget.state.bleDeviceName);
  }
  @override
  void dispose() { _urlCtrl.dispose(); _bleCtrl.dispose(); super.dispose(); }

  LumenColors get c => widget.c;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onDismiss,
      child: Container(
        color: (c.dark ? Colors.black : Colors.black).withOpacity(0.5),
        child: Center(child: GestureDetector(
          onTap: () {},
          child: Margin(margin: const EdgeInsets.all(24), child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: c.surface, borderRadius: BorderRadius.circular(28),
              boxShadow: [BoxShadow(color: c.dark ? Colors.black54 : Colors.black12, blurRadius: 40)],
            ),
            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Настройки', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.text, letterSpacing: -0.5)),
                GestureDetector(onTap: widget.onDismiss, child: Icon(Icons.close_rounded, color: c.muted)),
              ]),
              const SizedBox(height: 24),

              // Тема
              Text('Тема', style: TextStyle(fontSize: 12, color: c.muted, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              _SegControl(
                options: const ['Светлая', 'Тёмная'],
                selected: widget.darkMode ? 1 : 0,
                c: c,
                onSelect: (i) { if ((i == 1) != widget.darkMode) widget.onToggleDark(); },
              ),
              const SizedBox(height: 18),

              // Раскладка
              Text('Главный экран', style: TextStyle(fontSize: 12, color: c.muted, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              _SegControl(
                options: const ['A — Кнопка', 'B — Плитки', 'C — История'],
                selected: ['A','B','C'].indexOf(widget.layout),
                c: c,
                onSelect: (i) => widget.onLayoutChange(['A','B','C'][i]),
              ),
              const SizedBox(height: 18),

              // URL сервера
              Text('URL сервера', style: TextStyle(fontSize: 12, color: c.muted, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              _LTextField(controller: _urlCtrl, hint: 'https://...', c: c),
              const SizedBox(height: 12),

              Text('Имя BLE-устройства', style: TextStyle(fontSize: 12, color: c.muted, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              _LTextField(controller: _bleCtrl, hint: 'ESP32-CAM', c: c),
              const SizedBox(height: 24),

              // Модель
              _ModelStatusTile(c: c, model: widget.state.localModel),
              const SizedBox(height: 24),

              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: widget.onDismiss,
                  child: Container(height: 52, alignment: Alignment.center,
                    decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(14)),
                    child: Text('Отмена', style: TextStyle(color: c.muted, fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                )),
                const SizedBox(width: 12),
                Expanded(child: GestureDetector(
                  onTap: () {
                    widget.state.saveSettings(_urlCtrl.text, _bleCtrl.text);
                    widget.onDismiss();
                  },
                  child: Container(height: 52, alignment: Alignment.center,
                    decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: c.accent.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4))]),
                    child: const Text('Сохранить', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                )),
              ]),
            ])),
          )),
        )),
      ),
    );
  }
}

class Margin extends StatelessWidget {
  final EdgeInsets margin;
  final Widget child;
  const Margin({super.key, required this.margin, required this.child});
  @override
  Widget build(BuildContext context) => Padding(padding: margin, child: child);
}

class _SegControl extends StatelessWidget {
  final List<String> options;
  final int selected;
  final LumenColors c;
  final ValueChanged<int> onSelect;
  const _SegControl({required this.options, required this.selected, required this.c, required this.onSelect});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(12)),
    child: Row(children: options.asMap().entries.map((e) {
      final active = e.key == selected;
      return Expanded(child: GestureDetector(
        onTap: () => onSelect(e.key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 36, alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? c.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: active ? [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4)] : null,
          ),
          child: Text(e.value,
            style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: active ? (c.dark ? c.text : LC.textL) : c.muted,
            )),
        ),
      ));
    }).toList()),
  );
}

class _LTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final LumenColors c;
  const _LTextField({required this.controller, required this.hint, required this.c});
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    style: TextStyle(color: c.text, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: c.faint, fontSize: 13),
      filled: true, fillColor: c.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.accent)),
    ),
  );
}

class _ModelStatusTile extends StatelessWidget {
  final LumenColors c;
  final LocalModelManager model;
  const _ModelStatusTile({required this.c, required this.model});

  @override
  Widget build(BuildContext context) {
    final status = model.status;
    final Color col = status == ModelStatus.ready ? c.success
        : status == ModelStatus.failed ? c.danger
        : c.accent;
    final String label = switch (status) {
      ModelStatus.notDownloaded  => 'Не скачана',
      ModelStatus.downloadingModel => 'Скачивание модели (${(model.progress * 100).round()}%)',
      ModelStatus.downloadingMmproj => 'Скачивание vision (${(model.progress * 100).round()}%)',
      ModelStatus.loading        => 'Инициализация...',
      ModelStatus.ready          => 'Готова · Gemma 4 E2B',
      ModelStatus.failed         => model.errorMessage != null ? 'Ошибка: ${model.errorMessage!.substring(0, model.errorMessage!.length.clamp(0, 80))}' : 'Ошибка загрузки',
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: col.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
          child: Icon(status == ModelStatus.ready ? Icons.check_rounded : Icons.memory_rounded, color: col, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Локальная модель', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text)),
          Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
        ])),
        if (status == ModelStatus.notDownloaded || status == ModelStatus.failed)
          GestureDetector(
            onTap: status == ModelStatus.failed ? model.retryDownload : model.startDownload,
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(8)),
              child: Text('Скачать', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
          ),
      ]),
    );
  }
}
