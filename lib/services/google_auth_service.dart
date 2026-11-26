import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'storage_service.dart';
import 'google_sheets_service.dart';

class GoogleUserProfile {
  final String id;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final Uint8List? photoBytes;

  GoogleUserProfile({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
    this.photoBytes,
  });
}

class GoogleAuthService {
  static final GoogleAuthService instance = GoogleAuthService._internal();
  factory GoogleAuthService() => instance;
  GoogleAuthService._internal();

  static const List<String> requiredScopes = [
    'email',
    'https://www.googleapis.com/auth/spreadsheets',
    'https://www.googleapis.com/auth/drive.file',
    'https://www.googleapis.com/auth/drive.metadata.readonly',
  ];

  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: requiredScopes,
  );

  StreamSubscription<GoogleSignInAccount?>? _accountSubscription;
  bool _initialized = false;
  GoogleSignInAccount? _currentAccount;

  final ValueNotifier<GoogleUserProfile?> currentUserNotifier =
      ValueNotifier<GoogleUserProfile?>(null);
  final ValueNotifier<bool> isLoadingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String?> errorMessageNotifier = ValueNotifier<String?>(null);

  GoogleUserProfile? get currentUser => currentUserNotifier.value;
  bool get isSignedIn => currentUserNotifier.value != null;

  Future<String?> get currentUserEmail async {
    if (currentUserNotifier.value?.email != null) {
      return currentUserNotifier.value!.email;
    }
    return StorageService.instance.getString('google_user_email');
  }

  Future<void> init() async {
    if (_initialized) return;

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _initialized = true;
      return;
    }

    try {
      // 1. Restore from local storage first for immediate offline UI
      final savedEmail = await StorageService.instance.getString('google_user_email');
      final savedName = await StorageService.instance.getString('google_user_name');
      final savedPhoto = await StorageService.instance.getString('google_user_photo');
      final savedPhotoB64 = await StorageService.instance.getString('google_user_photo_b64');
      final savedId = await StorageService.instance.getString('google_user_id');

      Uint8List? cachedBytes;
      if (savedPhotoB64 != null && savedPhotoB64.isNotEmpty) {
        try {
          cachedBytes = base64Decode(savedPhotoB64);
        } catch (_) {}
      }

      if (savedEmail != null && savedEmail.isNotEmpty) {
        currentUserNotifier.value = GoogleUserProfile(
          id: savedId ?? '',
          email: savedEmail,
          displayName: savedName,
          photoUrl: savedPhoto,
          photoBytes: cachedBytes,
        );
        if (savedPhoto != null && savedPhoto.isNotEmpty && cachedBytes == null) {
          unawaited(_cachePhotoBytes(savedPhoto));
        }
      }

      _accountSubscription = _googleSignIn.onCurrentUserChanged.listen(
        (GoogleSignInAccount? account) {
          if (account != null) {
            _updateUser(account);
          } else {
            _clearUser();
          }
        },
        onError: (Object error) {
          if (kDebugMode) {
            print('Google Auth Stream Error: $error');
          }
        },
      );

      // Attempt silent sign in if previously authorized
      final account = await _googleSignIn.signInSilently();
      if (account != null) {
        _updateUser(account);
      }
      _initialized = true;
    } catch (e) {
      if (kDebugMode) {
        print('Google Auth init error: $e');
      }
    }
  }

  Future<void> _cachePhotoBytes(String photoUrl) async {
    try {
      if (!await StorageService.instance.hasNetworkConnection()) return;
      final res = await http.get(Uri.parse(photoUrl)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        await StorageService.instance.setString('google_user_photo_b64', base64Encode(res.bodyBytes));
        final curr = currentUserNotifier.value;
        if (curr != null && curr.photoUrl == photoUrl) {
          currentUserNotifier.value = GoogleUserProfile(
            id: curr.id,
            email: curr.email,
            displayName: curr.displayName,
            photoUrl: curr.photoUrl,
            photoBytes: res.bodyBytes,
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _updateUser(GoogleSignInAccount user) async {
    _currentAccount = user;
    final existingBytes = currentUserNotifier.value?.photoBytes;
    final profile = GoogleUserProfile(
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoUrl,
      photoBytes: existingBytes,
    );
    currentUserNotifier.value = profile;
    errorMessageNotifier.value = null;

    await StorageService.instance.setString('google_user_email', user.email);
    if (user.displayName != null) {
      await StorageService.instance.setString('google_user_name', user.displayName!);
    }
    if (user.photoUrl != null) {
      await StorageService.instance.setString('google_user_photo', user.photoUrl!);
      unawaited(_cachePhotoBytes(user.photoUrl!));
    }
    await StorageService.instance.setString('google_user_id', user.id);
  }

  Future<void> _clearUser() async {
    _currentAccount = null;
    currentUserNotifier.value = null;
    await StorageService.instance.remove('google_user_email');
    await StorageService.instance.remove('google_user_name');
    await StorageService.instance.remove('google_user_photo');
    await StorageService.instance.remove('google_user_photo_b64');
    await StorageService.instance.remove('google_user_id');
    await GoogleSheetsService.instance.clearActiveSpreadsheetInfo();
  }

  Future<GoogleUserProfile?> signIn() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return null;
    }
    try {
      isLoadingNotifier.value = true;
      errorMessageNotifier.value = null;
      if (!_initialized) {
        await init();
      }

      final account = await _googleSignIn.signIn();
      if (account != null) {
        await _updateUser(account);
        return currentUserNotifier.value;
      }
      return null;
    } catch (e) {
      final msg = 'Google Sign-In error: $e';
      errorMessageNotifier.value = msg;
      if (kDebugMode) print(msg);
      return null;
    } finally {
      isLoadingNotifier.value = false;
    }
  }

  Future<String?> getAccessToken() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return null;
    }
    try {
      var account = _currentAccount ?? _googleSignIn.currentUser;
      account ??= await _googleSignIn.signInSilently();
      if (account == null) return null;

      final auth = await account.authentication;
      return auth.accessToken;
    } catch (e) {
      if (kDebugMode) print('getAccessToken error: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      await _clearUser();
      return;
    }
    try {
      isLoadingNotifier.value = true;
      await _googleSignIn.signOut();
      await _clearUser();
    } catch (e) {
      errorMessageNotifier.value = 'Failed to sign out: $e';
    } finally {
      isLoadingNotifier.value = false;
    }
  }

  Future<void> disconnect() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      await _clearUser();
      return;
    }
    try {
      isLoadingNotifier.value = true;
      await _googleSignIn.disconnect();
      await _clearUser();
    } catch (e) {
      errorMessageNotifier.value = 'Failed to disconnect: $e';
    } finally {
      isLoadingNotifier.value = false;
    }
  }

  void dispose() {
    _accountSubscription?.cancel();
  }
}
