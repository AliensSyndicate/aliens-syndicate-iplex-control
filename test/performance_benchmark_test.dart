import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/tokens.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/graphite_material.dart';

void main() {
  test('benchmark GraphiteMaterialPainter before optimization', () {
    const size = Size(350, 56);
    final painterElevated = GraphiteMaterialPainter(
      circle: false,
      recessed: false,
      radius: AppRadii.pill,
      finish: GraphiteFinish.button,
    );
    final painterRecessed = GraphiteMaterialPainter(
      circle: false,
      recessed: true,
      radius: AppRadii.pill,
      finish: GraphiteFinish.button,
    );

    // Warm up
    final warmRecorder = ui.PictureRecorder();
    final warmCanvas = Canvas(warmRecorder);
    painterElevated.paint(warmCanvas, size);
    painterRecessed.paint(warmCanvas, size);
    warmRecorder.endRecording();

    // Benchmark 1000 paint operations
    final swElevated = Stopwatch()..start();
    for (var i = 0; i < 1000; i++) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      painterElevated.paint(canvas, size);
      recorder.endRecording();
    }
    swElevated.stop();

    final swRecessed = Stopwatch()..start();
    for (var i = 0; i < 1000; i++) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      painterRecessed.paint(canvas, size);
      recorder.endRecording();
    }
    swRecessed.stop();

    debugPrint(
      '1000 elevated paints: ${swElevated.elapsedMicroseconds} us (${swElevated.elapsedMicroseconds / 1000} us/paint)',
    );
    debugPrint(
      '1000 recessed paints: ${swRecessed.elapsedMicroseconds} us (${swRecessed.elapsedMicroseconds / 1000} us/paint)',
    );
  });
}
