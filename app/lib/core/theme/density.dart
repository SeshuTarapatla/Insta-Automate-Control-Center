// DESIGN_SYSTEM.md §1.8 — density is a multiplier applied to `SpacingTokens`
// and `type.scale` at theme-build time, not a concept any feature file knows
// about. The picker that lets a user choose `compact` lands in V2.4; V2.1
// only wires the enum and the scale it applies so `build_theme.dart` has a
// stable shape to build against.
enum Density {
  comfortable,
  compact;

  double get spaceScale => switch (this) {
    Density.comfortable => 1.0,
    Density.compact => 0.75,
  };

  double get typeScale => switch (this) {
    Density.comfortable => 1.0,
    Density.compact => 0.95,
  };
}
