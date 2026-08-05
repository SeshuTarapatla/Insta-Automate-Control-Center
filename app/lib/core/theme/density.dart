// DESIGN_SYSTEM.md §1.8 — density is a multiplier applied to `SpacingTokens`
// and `typography.scale` at theme-build time, not a concept any feature file
// knows about. Three tiers, low to high: `compact` (0.75×/0.95×) < `comfortable`
// (1.0×/1.0×, the default) < `spacious` (1.15×/1.05×) — added 2026-08-05 per
// the user's own request, once `compact` existed and made "one more tier,
// roomier than the default" an obvious next ask.
enum Density {
  compact,
  comfortable,
  spacious;

  double get spaceScale => switch (this) {
    Density.compact => 0.75,
    Density.comfortable => 1.0,
    Density.spacious => 1.15,
  };

  double get typeScale => switch (this) {
    Density.compact => 0.95,
    Density.comfortable => 1.0,
    Density.spacious => 1.05,
  };
}
