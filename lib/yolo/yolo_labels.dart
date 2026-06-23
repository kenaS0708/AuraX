/// Классы модели blind_v3 для слабовидящих.
/// 0=crosswalk 1=stairs 2=door 3=pothole 4=pole
/// 5=person 6=vehicle 7=traffic_light 8=obstacle
class YoloLabels {
  static const List<String> names = [
    'crosswalk', 'stairs', 'door', 'pothole', 'pole',
    'person', 'vehicle', 'traffic_light', 'obstacle',
  ];

  static const Map<int, int> priority = {
    1: 1, // stairs
    2: 1, // door
    0: 1, // crosswalk
    3: 1, // pothole
    4: 2, // pole
    5: 2, // person
    6: 2, // vehicle
    7: 3, // traffic_light
    8: 2, // obstacle
  };

  static const Map<int, String> russian = {
    0: 'пешеходный переход',
    1: 'лестница',
    2: 'дверь',
    3: 'яма',
    4: 'столб',
    5: 'человек',
    6: 'транспорт',
    7: 'светофор',
    8: 'препятствие',
  };
}
