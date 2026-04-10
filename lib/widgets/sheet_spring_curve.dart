import 'package:flutter/physics.dart';
import 'package:flutter/animation.dart';

/// A spring-based curve that pre-samples a SpringSimulation for fast lookup.
/// Fast entry, slight overshoot, then settle — feels alive and physical.
///
/// Note: This extends Curve but allows overshoot (values > 1.0).
/// The transform method is overridden directly to bypass the 0.0-1.0 assertion.
class SheetSpringCurve extends Curve {
  const SheetSpringCurve._();
  static const instance = SheetSpringCurve._();

  static const spring = SpringDescription(
    mass: 1.0,
    stiffness: 177.8,
    damping: 23.0,
  );

  static final List<double> _samples = _buildSamples();

  static List<double> _buildSamples() {
    const count = 1000;
    final sim = SpringSimulation(spring, 0.0, 1.0, 8.0);
    const duration = 0.8;
    final samples = <double>[];
    for (int i = 0; i <= count; i++) {
      final t = i / count * duration;
      samples.add(sim.x(t));
    }
    samples[count] = 1.0;
    return samples;
  }

  /// Override transform directly to allow overshoot values > 1.0.
  /// The default Curve.transform asserts output is in [0.0, 1.0] in debug mode.
  @override
  double transform(double t) {
    if (t == 0.0 || t == 1.0) return t;
    return transformInternal(t);
  }

  @override
  double transformInternal(double t) {
    final index = t * (_samples.length - 1);
    final lower = index.floor();
    final upper = index.ceil();
    if (lower == upper) return _samples[lower];
    final fraction = index - lower;
    return _samples[lower] + (_samples[upper] - _samples[lower]) * fraction;
  }
}
