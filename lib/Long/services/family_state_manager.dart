import 'package:flutter/foundation.dart';
import '../models/family_model.dart';
import '../models/family_member_model.dart';
import 'family_service_interface.dart';
import 'mock_data_service.dart';

class FamilyStateManager extends ChangeNotifier {
  static final FamilyStateManager _instance = FamilyStateManager._internal();
  factory FamilyStateManager() => _instance;
  FamilyStateManager._internal();

  IFamilyService _service = MockDataService();

  void setService(IFamilyService service) {
    _service = service;
    notifyListeners();
  }

  IFamilyService get service => _service;

  String? _currentFamilyId;
  String? get currentFamilyId => _currentFamilyId;

  FamilyModel? _currentFamily;
  FamilyModel? get currentFamily => _currentFamily;

  List<FamilyModel> _myFamilies = [];
  List<FamilyModel> get myFamilies => _myFamilies;

  List<FamilyMemberModel> _currentMembers = [];
  List<FamilyMemberModel> get currentMembers => _currentMembers;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      _myFamilies = await _service.getMyFamilies();
      if (_myFamilies.isNotEmpty) {
        _currentFamily = await _service.getCurrentFamily() ?? _myFamilies.first;
        _currentFamilyId = _currentFamily?.id;
        if (_currentFamilyId != null) {
          _currentMembers = await _service.getFamilyMembers(familyId: _currentFamilyId);
        }
      }
    } catch (e) {
      debugPrint('FamilyStateManager initialize error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> switchFamily(String familyId) async {
    if (_currentFamilyId == familyId) return;
    _isLoading = true;
    notifyListeners();

    try {
      await _service.switchFamily(familyId);
      _myFamilies = await _service.getMyFamilies();
      _currentFamily = _myFamilies.firstWhere(
        (f) => f.id == familyId,
        orElse: () => _myFamilies.first,
      );
      _currentFamilyId = _currentFamily?.id;
      if (_currentFamilyId != null) {
        _currentMembers = await _service.getFamilyMembers(familyId: _currentFamilyId);
      }
    } catch (e) {
      debugPrint('FamilyStateManager switchFamily error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> reload() async {
    try {
      _myFamilies = await _service.getMyFamilies();
      _currentFamily = await _service.getCurrentFamily();
      _currentFamilyId = _currentFamily?.id;
      if (_currentFamilyId != null) {
        _currentMembers = await _service.getFamilyMembers(familyId: _currentFamilyId);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('FamilyStateManager reload error: $e');
    }
  }
}
