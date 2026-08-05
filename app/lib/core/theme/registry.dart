// id -> builder, ordered for the theme picker (THEMES.md §9, same order as
// THEMES.md §1's table). Adding a theme later is meant to be exactly this:
// one file in `themes/`, one line here — THEMES.md §10's closing point, and
// the reason the token layer was built before any of the five remaining
// themes.
import 'themes/classic.dart';
import 'themes/command_deck.dart';
import 'themes/daylight.dart';
import 'themes/mica.dart';
import 'themes/nocturne.dart';
import 'themes/swiss.dart';
import 'tokens.dart';

const themeRegistry = <ThemeId, AppTokens Function()>{
  ThemeId.classic: buildClassicTokens,
  ThemeId.commandDeck: buildCommandDeckTokens,
  ThemeId.nocturne: buildNocturneTokens,
  ThemeId.mica: buildMicaTokens,
  ThemeId.daylight: buildDaylightTokens,
  ThemeId.swiss: buildSwissTokens,
};

AppTokens buildTokensFor(ThemeId id) => themeRegistry[id]!();
