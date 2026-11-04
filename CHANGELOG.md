# Changelog

## [1.0.5] - 2026-11-04

### Fixed
- A game no longer crashes when an outdated plugin is installed alongside:
  shared modules left behind by an older plugin are replaced by this
  plugin's own copy instead of being used as they are.

## [1.0.4] - 2026-11-04

### Changed
- Uses less memory: the game loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unplayed.
- Uses less memory: the questions load when the game opens, only for the
  language played, and are freed when it closes.

## [1.0.3] - 2026-11-03

### Changed
- Picks up game-common 1.11.0: the shared on-screen keyboard (where used)
  gives every key the same letter size, and the no-repeat history helper.

## [1.0.2] - 2026-11-02

### Changed
- Picks up game-common 1.10.0: the shared Tools → Games menu also lists
  the games' new "· multiplayer" entries under Party & quiz.

## [1.0.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.0.0] - 2026-10-30

### Added
- First release: numeric trivia for 2 to 8 players on one reader, with secret guesses on a number pad and a hand-over screen between players.
- Three scoring modes: closest, closest without going over, and betting (chips on the sorted guesses, paid at the slot's odds).
- 803 English and 811 French questions in 16 categories, each with a unit and a one-line fact; category filter; 5, 10 or 15 questions per game.
- Player names remembered; game saved and resumed; "New game" in the action bar once the game is over.
