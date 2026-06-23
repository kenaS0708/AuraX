import 'yolo_detector.dart';
import 'yolo_labels.dart';

/// Описание сцены для слабовидящих.
/// Классы blind_v3:
/// 0=crosswalk 1=stairs 2=door 3=pothole 4=pole
/// 5=person 6=vehicle 7=traffic_light 8=obstacle
class SceneDescriber {
  static String describe(List<Detection> detections) {
    if (detections.isEmpty) return 'Путь свободен.';

    detections.sort((a, b) {
      final pc = a.priority.compareTo(b.priority);
      return pc != 0 ? pc : b.area.compareTo(a.area);
    });

    final sentences = <String>[];

    // ── Лестница ───────────────────────────────────────────
    final stairs = detections.where((d) => d.classId == 1).toList();
    if (stairs.isNotEmpty) {
      sentences.add('Лестница ${stairs.first.side}, ${stairs.first.distance}.');
    }

    // ── Дверь ─────────────────────────────────────────────
    final doors = detections.where((d) => d.classId == 2).toList();
    if (doors.isNotEmpty && sentences.length < 2) {
      sentences.add('Дверь ${doors.first.side}.');
    }

    // ── Яма ───────────────────────────────────────────────
    final holes = detections.where((d) => d.classId == 3 && d.area > 0.015).toList();
    if (holes.isNotEmpty && sentences.length < 2) {
      sentences.add('Яма ${holes.first.side}.');
    }

    // ── Пешеходный переход ────────────────────────────────
    final cross = detections.where((d) => d.classId == 0).toList();
    if (cross.isNotEmpty && sentences.length < 2) {
      sentences.add('Пешеходный переход ${cross.first.side}.');
    }

    // ── Столб ─────────────────────────────────────────────
    final poles = detections.where((d) => d.classId == 4 && d.area > 0.01).toList();
    if (poles.isNotEmpty && sentences.length < 2) {
      sentences.add('Столб ${poles.first.side}.');
    }

    // ── Транспорт ─────────────────────────────────────────
    final vehicles = detections.where((d) => d.classId == 6).toList();
    if (vehicles.isNotEmpty && sentences.length < 2) {
      final v = vehicles.first;
      final close = v.area > 0.06 ? ', близко' : '';
      sentences.add('Транспорт ${v.side}$close.');
    }

    // ── Люди ──────────────────────────────────────────────
    final people = detections.where((d) => d.classId == 5).toList();
    if (people.isNotEmpty && sentences.length < 2) {
      final p = people.first;
      if (p.area > 0.02) {
        sentences.add(people.length == 1
            ? 'Человек ${p.side}, ${p.distance}.'
            : '${_personCount(people.length)} рядом.');
      }
    }

    // ── Препятствие ───────────────────────────────────────
    final obstacles = detections.where((d) => d.classId == 8 && d.area > 0.02).toList();
    if (obstacles.isNotEmpty && sentences.length < 2) {
      sentences.add('Препятствие ${obstacles.first.side}.');
    }

    if (sentences.isEmpty) return 'Путь свободен.';
    return sentences.take(2).join(' ');
  }

  static bool canAnswerQuery(String q, List<Detection> d) {
    final query = q.toLowerCase();
    return _has(query, ['дверь', 'вход', 'выход', 'лестниц', 'ступень',
        'переход', 'зебра', 'столб', 'яма', 'машин', 'транспорт', 'человек', 'свободно']);
  }

  static String answerQuery(String query, List<Detection> detections) {
    final q = query.toLowerCase();
    if (_has(q, ['дверь', 'вход', 'выход'])) {
      final d = detections.where((d) => d.classId == 2).toList();
      if (d.isEmpty) return 'Двери не вижу.';
      return 'Дверь ${d.first.side}, ${d.first.distance}.';
    }
    if (_has(q, ['лестниц', 'ступень'])) {
      final d = detections.where((d) => d.classId == 1).toList();
      if (d.isEmpty) return 'Лестницы не вижу.';
      return 'Лестница ${d.first.side}, ${d.first.distance}.';
    }
    if (_has(q, ['переход', 'зебра'])) {
      final d = detections.where((d) => d.classId == 0).toList();
      if (d.isEmpty) return 'Перехода не вижу.';
      return 'Пешеходный переход ${d.first.side}.';
    }
    if (_has(q, ['свободно', 'пройти'])) {
      final danger = detections.where((d) => [1, 2, 3, 4].contains(d.classId)).toList();
      if (danger.isEmpty) return 'Путь свободен.';
      return '${_cap(YoloLabels.russian[danger.first.classId]!)} ${danger.first.side}.';
    }
    if (_has(q, ['человек', 'люди'])) {
      final d = detections.where((d) => d.classId == 5).toList();
      if (d.isEmpty) return 'Людей не вижу.';
      return '${_personCount(d.length)} ${d.first.side}.';
    }
    return describe(detections);
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  static String _personCount(int n) => n == 1 ? '1 человек' : n <= 4 ? '$n человека' : '$n человек';
  static bool _has(String t, List<String> kw) => kw.any(t.contains);
}
