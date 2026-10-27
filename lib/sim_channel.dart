import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// جسر التواصل مع كود أندرويد (Kotlin).
class SimChannel {
  static const _ch = MethodChannel('sim_channel');

  static Future<List<Map>> getSims() async {
    final r = await _ch.invokeMethod<List>('getSims');
    return (r ?? const []).map((e) => Map.from(e as Map)).toList();
  }

  static Future<Map> getConfig() async =>
      Map.from(await _ch.invokeMethod('getConfig') as Map);

  static Future<void> setConfig(Map<String, dynamic> m) =>
      _ch.invokeMethod('setConfig', m);

  static Future<bool> hasRole() async =>
      (await _ch.invokeMethod<bool>('hasScreeningRole')) ?? false;

  static Future<void> requestRole() async {
    try {
      await _ch.invokeMethod('requestScreeningRole');
    } catch (e) {
      debugPrint('requestRole failed: $e');
    }
  }

  static Future<void> openDataSettings() async {
    try {
      await _ch.invokeMethod('openDataSettings');
    } catch (e) {
      debugPrint('openDataSettings failed: $e');
    }
  }
}

/// أدوات مشتركة للأرقام (تدعم الأرقام العربية والفارسية).
class Num {
  /// يحوّل الأرقام العربية/الهندية إلى 0-9 ويُبقي الأرقام فقط.
  static String digits(String s) {
    final b = StringBuffer();
    for (final c in s.runes) {
      if (c >= 0x30 && c <= 0x39) {
        b.writeCharCode(c);
      } else if (c >= 0x660 && c <= 0x669) {
        b.writeCharCode(0x30 + c - 0x660);
      } else if (c >= 0x6F0 && c <= 0x6F9) {
        b.writeCharCode(0x30 + c - 0x6F0);
      }
    }
    return b.toString();
  }

  static bool same(String a, String b) {
    final x = digits(a), y = digits(b);
    if (x.length < 6 || y.length < 6) return false;
    final n = x.length < y.length ? x.length : y.length;
    final k = n < 8 ? n : 8;
    return x.substring(x.length - k) == y.substring(y.length - k);
  }
}
