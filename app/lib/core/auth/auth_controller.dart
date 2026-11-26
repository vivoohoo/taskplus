import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../config.dart';
import 'token_store.dart';

class AppUser {
  AppUser({required this.id, required this.name, required this.role, this.departmentId});
  final String id;
  final String name;
  final String role;
  final String? departmentId;

  factory AppUser.fromJson(Map<String, dynamic> j) =>
      AppUser(id: j['id'] as String, name: j['name'] as String, role: j['role'] as String, departmentId: j['departmentId'] as String?);
}

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(
      baseUrl: AppConfig.apiBaseUrl,
      tokens: ref.watch(tokenStoreProvider),
      onSignedOut: () => ref.read(authProvider.notifier).signedOut(),
    ));

/// Who is signed in: null when nobody. Loading while stored tokens are checked at start-up.
final authProvider = AsyncNotifierProvider<AuthController, AppUser?>(AuthController.new);

class AuthController extends AsyncNotifier<AppUser?> {
  Dio get _dio => ref.read(apiClientProvider).dio;
  TokenStore get _tokens => ref.read(tokenStoreProvider);

  @override
  Future<AppUser?> build() async {
    if (await _tokens.read() == null) return null;
    try {
      return AppUser.fromJson((await _dio.get('/me')).data as Map<String, dynamic>);
    } on DioException {
      return null; // offline or signed out: show sign-in
    }
  }

  Future<void> requestOtp(String phone) async {
    try {
      await _dio.post('/auth/otp/request', data: {'phone': phone}, options: Options(extra: {'noAuth': true}));
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> verifyOtp(String phone, String code) async {
    try {
      final r = await _dio.post('/auth/otp/verify', data: {'phone': phone, 'code': code}, options: Options(extra: {'noAuth': true}));
      await _tokens.save(r.data['accessToken'] as String, r.data['refreshToken'] as String);
      state = AsyncData(AppUser.fromJson(r.data['user'] as Map<String, dynamic>));
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> signOut() async {
    await _tokens.clear();
    state = const AsyncData(null);
  }

  /// Refresh failed: the tokens are already cleared.
  void signedOut() => state = const AsyncData(null);
}
