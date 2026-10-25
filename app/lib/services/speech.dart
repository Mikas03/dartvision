import 'speech_stub.dart' if (dart.library.js_interop) 'speech_web.dart' as impl;

/// Sprachansage über die Sprachausgabe des Browsers (Web Speech API, Deutsch).
class Speech {
  Speech._();

  static bool enabled = false;

  /// Auf dem iPhone muss die Sprachausgabe einmal durch einen Tipp "freigeschaltet" werden –
  /// das passiert beim Spielstart.
  static void unlock() => impl.unlock();

  static void say(String text) {
    if (enabled) impl.speak(text);
  }
}
