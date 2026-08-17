import 'package:flutter/foundation.dart';

import '../../data/models/farm.dart';
import '../../data/repositories/farm_repository.dart';

class FarmProvider extends ChangeNotifier {
  final FarmRepository _repo = FarmRepository();

  List<Farm> _farms = [];
  bool _loading = false;

  List<Farm> get farms => _farms;
  bool get loading => _loading;

  Future<void> loadFarms() async {
    _loading = true;
    notifyListeners();
    _farms = await _repo.getAllFarms();
    _loading = false;
    notifyListeners();
  }

  Future<Farm> createFarm({required String name, String? description}) async {
    final farm = await _repo.createFarm(name: name, description: description);
    await loadFarms();
    return farm;
  }

  Future<void> deleteFarm(String id) async {
    await _repo.deleteFarm(id);
    await loadFarms();
  }
}
