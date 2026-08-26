import 'dart:convert';
import 'package:flutter/foundation.dart';

class AuthUtils {
  static bool isTokenExpired(String? token) {
    if (token == null) return true;
    try {
      final decodedToken = json.decode(
        utf8.decode(base64.decode(base64.normalize(token.split('.')[1]))),
      );
      final expiryTime = DateTime.fromMillisecondsSinceEpoch(decodedToken['exp'] * 1000);
      return DateTime.now().isAfter(expiryTime);
    } catch (e) {
      debugPrint('Erreur lors de la vérification du token : $e');
      return true;
    }
  }
}
