// id -> builder, ordered for the theme picker (THEMES.md §9). Adding a theme
// later is meant to be exactly this: one file in `themes/`, one line here —
// THEMES.md §10's closing point, and the reason the token layer was built
// before any of the five remaining themes.
import 'themes/classic.dart';
import 'tokens.dart';

const themeRegistry = <ThemeId, AppTokens Function()>{ThemeId.classic: buildClassicTokens};

AppTokens buildTokensFor(ThemeId id) => themeRegistry[id]!();
