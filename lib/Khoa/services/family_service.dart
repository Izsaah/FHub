import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/family.dart';
import '../models/family_member.dart';

class FamilyService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// ID của user đang đăng nhập Supabase Auth.
  String get currentUserId {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception(
        'Chưa đăng nhập. Không thể xác định người dùng hiện tại.',
      );
    }

    return user.id;
  }

  /// Tạo một mã gia đình dạng ABCD-1234.
  String _generateJoinCode() {
    const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const numbers = '0123456789';

    final random = Random();

    final part1 = List.generate(
      4,
      (_) => letters[random.nextInt(letters.length)],
    ).join();

    final part2 = List.generate(
      4,
      (_) => numbers[random.nextInt(numbers.length)],
    ).join();

    return '$part1-$part2';
  }

  /// Kiểm tra mã gia đình đã tồn tại hay chưa.
  Future<bool> _joinCodeExists(String code) async {
    final result = await _supabase
        .from('families')
        .select('id')
        .eq('join_code', code)
        .maybeSingle();

    return result != null;
  }

  /// Tạo mã gia đình duy nhất.
  Future<String> _generateUniqueJoinCode() async {
    for (int i = 0; i < 10; i++) {
      final code = _generateJoinCode();

      final exists = await _joinCodeExists(code);

      if (!exists) {
        return code;
      }
    }

    throw Exception('Không thể tạo mã gia đình duy nhất. Vui lòng thử lại.');
  }

  /// Tạo family mới.
  Future<Family> createFamily({required String name}) async {
    final userId = currentUserId;

    final joinCode = await _generateUniqueJoinCode();

    try {
      final familyResponse = await _supabase
          .from('families')
          .insert({'name': name, 'join_code': joinCode, 'owner_id': userId})
          .select()
          .single();

      final family = Family.fromMap(familyResponse);

      try {
        await _supabase.from('family_members').insert({
          'family_id': family.id,
          'user_id': userId,
          'role': 'OWNER',
        });
      } catch (e) {
        // Nếu tạo membership thất bại thì xóa family vừa tạo.
        try {
          await _supabase.from('families').delete().eq('id', family.id);
        } catch (_) {}

        rethrow;
      }

      return family;
    } on PostgrestException catch (e) {
      throw Exception(
        e.message.isNotEmpty ? e.message : 'Không thể tạo gia đình.',
      );
    } catch (e) {
      throw Exception('Không thể tạo gia đình: $e');
    }
  }

  /// Tìm family bằng join code.
  Future<Family?> findFamilyByJoinCode(String code) async {
    try {
      final response = await _supabase
          .from('families')
          .select()
          .eq('join_code', code.toUpperCase())
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return Family.fromMap(response);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  /// Kiểm tra user hiện tại đã là member của family hay chưa.
  Future<bool> isMemberOfFamily(String familyId) async {
    final userId = currentUserId;

    final response = await _supabase
        .from('family_members')
        .select('family_id')
        .eq('family_id', familyId)
        .eq('user_id', userId)
        .maybeSingle();

    return response != null;
  }

  /// Tham gia family bằng join code.
  Future<Family> joinFamily({required String joinCode}) async {
    final userId = currentUserId;

    final normalizedCode = joinCode.trim().toUpperCase();

    if (normalizedCode.isEmpty) {
      throw Exception('Vui lòng nhập mã gia đình.');
    }

    final family = await findFamilyByJoinCode(normalizedCode);

    if (family == null) {
      throw Exception('Không tìm thấy gia đình với mã "$normalizedCode".');
    }

    final alreadyMember = await isMemberOfFamily(family.id);

    if (alreadyMember) {
      throw Exception('Bạn đã là thành viên của gia đình này.');
    }

    try {
      await _supabase.from('family_members').insert({
        'family_id': family.id,
        'user_id': userId,
        'role': 'MEMBER',
      });

      return family;
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw Exception('Bạn đã là thành viên của gia đình này.');
      }

      throw Exception(
        e.message.isNotEmpty ? e.message : 'Không thể tham gia gia đình.',
      );
    } catch (e) {
      throw Exception('Không thể tham gia gia đình: $e');
    }
  }

  /// Lấy danh sách family mà user hiện tại tham gia.
  Future<List<Family>> getMyFamilies() async {
    final userId = currentUserId;

    try {
      final response = await _supabase
          .from('family_members')
          .select('''
            family_id,
            families (
              id,
              name,
              join_code,
              owner_id,
              created_at
            )
          ''')
          .eq('user_id', userId);

      final families = <Family>[];

      for (final item in response) {
        final familyData = item['families'];

        if (familyData != null && familyData is Map<String, dynamic>) {
          families.add(Family.fromMap(familyData));
        }
      }

      return families;
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception('Không thể tải danh sách gia đình: $e');
    }
  }

  /// Lấy members của một family.
  Future<List<FamilyMember>> getFamilyMembers(String familyId) async {
    try {
      final response = await _supabase
          .from('family_members')
          .select()
          .eq('family_id', familyId);

      return response
          .map<FamilyMember>((item) => FamilyMember.fromMap(item))
          .toList();
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  /// Lấy family theo ID.
  Future<Family?> getFamilyById(String familyId) async {
    try {
      final response = await _supabase
          .from('families')
          .select()
          .eq('id', familyId)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return Family.fromMap(response);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }
}
