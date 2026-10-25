import 'package:web/web.dart' as web;

void unlock() => speak('', volume: 0);

void speak(String text, {double volume = 1}) {
  try {
    final synth = web.window.speechSynthesis;
    synth.cancel(); // laufende Ansage abbrechen, damit nichts nachhinkt
    final utterance = web.SpeechSynthesisUtterance(text)
      ..lang = 'de-DE'
      ..volume = volume
      ..rate = 1.05;
    synth.speak(utterance);
  } catch (_) {
    // Browser ohne Sprachausgabe – dann eben still
  }
}
