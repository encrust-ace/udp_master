import 'dart:math';

double calculateVolume(List<double> samples) {
  if (samples.isEmpty) return 0;
  double sum = 0;
  for (var sample in samples) {
    sum += sample * sample;
  }
  return sqrt(sum / samples.length); // use sqrt() from dart:math
}
