# Changelog

All notable changes to BattlePad are documented here.  The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
follows semantic versioning.

## [0.6.3] - 2026-08-19

### Changed

- The mod description opens with the one-line summary and now leads every
  release's notes, so the launcher's version screens say what BattlePad is
  before what changed.

## [0.6.2] - 2026-08-18

### Changed

- Release housekeeping: CI-built archive from the corrected tree (README
  synced to current controls, publishing doc included), matching the index
  submission.

## [0.6.1] - 2026-08-17

### Changed

- RUN HOLD row in OPTIONS: the held-B run commit takes 1, 3, 5, 7 or 10
  seconds (default 3), and the progress ring paces itself to the choice.
- The right stick no longer selects menu items; commands live on the face
  buttons, moves on the d-pad and left stick.

## [0.6.0] - 2026-08-17

### Changed

- 3D BATTLES defaults to BATTLEPAD: current Dramatic Shape builds and the
  deck run well together, so the deck stays on inside staged battles, with
  CLASSIC one row away for older voxel builds.
- The manifest carries the GitHub home, so the launcher can offer updates.

## [0.5.1] - 2026-08-17

### Added

- 3D BATTLES row in OPTIONS: CLASSIC (default) hands every battle to the
  Dramatic Shape family mod's own presentation while one is active, so the
  staged 3D battles run exactly as they do without BattlePad; BATTLEPAD
  keeps the deck on there for whoever wants to try the combination.
- On-screen crash panel: with DEBUG LOG on, the last crash's message and
  stack trace are shown for the first minute of the next boot, ready to
  screenshot -- built for devices (Android) where the save directory's
  lua-error.log is unreachable.

## [0.5.0] - 2026-08-17

### Added

- DEBUG LOG row in OPTIONS (default OFF).  When on, BattlePad writes a
  plain-text trail -- session header with engine/game/pad/mods, battle
  starts and ends, claim stand-downs, input-capture faults, skin draw
  errors -- to battle_pad_log.txt under mod_compat/battle_pad/ in the save
  directory, beside the engine's own lua-error.log crash trace.  The two
  files together are what to send when something goes wrong.

## [0.4.1] - 2026-08-16

### Fixed

- A stick this mod has stood down from is now left completely alone.  The
  claim settle step force-centred the engine stick on every claimed frame
  regardless of the STICKS setting, so with a camera mod owning the sticks
  BattlePad began writing centred axes underneath that camera 60 times a
  second from the instant a battle opened.  Centring now happens once per
  claim, and only when BattlePad actually owns the sticks.  Covered by a
  mutation-tested regression check.
- The raw controller entry points and the battle text-area wrap are guarded:
  a fault inside BattlePad now forwards the event to the vanilla engine and
  logs, where before it could reach the player as a crash.

## [0.4.0] - 2026-08-16

### Changed

- The deck is two-step, like the classic flow: the command step shows only
  FIGHT / RUN / POKEMON / PACK, and the move compass appears after FIGHT.
  Every element has one fixed home -- pieces hide and unhide, nothing moves.
- Battle text gets the band to itself: no compass or cluster during intro,
  switch and turn text, so a press can only mean advance the text.  The
  amber NEXT line is the one queue indicator.
- Keyboard sessions show the key itself on each command button (Z / X /
  TAB / ESC) in place of the pad glyphs.
- Centering pass: the cluster clears the panel edges in every layout.

## [0.3.0] - 2026-08-16

### Added

- Gold (Gen 2) support, run and verified on a real Gold battle: the manifest
  claims games gen1 + gen2, so the launcher and mod manager show GEN 1+2.
  Gold gets its own arm -- no puppeteer, straight semantic calls into
  Gold's battle screen -- with the same deck, queueing, skins and options.
  The Bug-Catching Contest and catch tutorial keep Gold's classic menus.
- STICKS option (AUTO / ON / OFF): AUTO stands the radial sticks down
  beside a Dramatic Shape family mod; ON overrides the voxel camera.
- A keyboard shortcut legend on the deck when no gamepad is present.

## [0.2.1] - 2026-08-16

### Changed

- The cooldown spinners are retired; the greyed-in-place cards are the
  whole cooldown signal.
- Dramatic Shape family compatibility: when DRAMATIC_SHAPE (or a known
  fork) is active, BattlePad's radial stick selection stands down
  automatically and the sticks belong to the staged battle camera; the
  d-pad and face buttons carry the full deck.

## [0.2.0] - 2026-08-16

### Changed

- The battle band has one fixed layout across every state: the move compass
  and command cluster keep the same position and size whether you are
  choosing an action or the turn is resolving.  During resolution the same
  cards grey out under their cooldown spinners instead of a second, smaller
  compass appearing elsewhere -- the UI holds still.
- Moves that can no longer be committed (no PP, disabled, or mid-cooldown)
  read as greyed-out cards in place.
- The queue helper line is gone; the amber NEXT tag on the queued card (or
  a NEXT line for a queued command) is the only queue indicator.
- Message text renders in the band's left column beside the compass.

## [0.1.2] - 2026-08-16

### Changed

- Verified against the newest engine (origin/dev, post-v0.1.97): the full
  end-to-end suite passes on the current battle code, including the
  refactored chooseMenu command path.
- The buildScreen wrap is variadic, matching the engine's own
  `buildScreen(id, ...)` so multi-argument screens pass through whole.

### Added

- Generation 2 readiness for the engine's new Gold support: DARK and STEEL
  type colors on the move cards.  The mod carries no version branches and
  loads clean against the version-neutral fixture dataset; the engine
  auto-enables it per version, Gold included.

## [0.1.1] - 2026-08-16

### Fixed

- The classic UI is now fully hidden in every deck state: a battle adopted
  mid-move-select (BattlePad toggled on mid-battle) is walked back to the
  command menu before the deck takes over, so the classic move list and
  TYPE/PP panel -- which draw above the deck's band -- can never share a
  frame with it.

## [0.1.0] - 2026-08-16

### Added

- The command deck: one modern battle menu replaces the FIGHT / PKMN /
  ITEM / RUN and move-list two-step.  D-pad directions fire the four moves
  (north / west / east / south); face buttons are FIGHT, RUN (held),
  POKEMON and PACK.
- Radial stick selection: the left stick highlights and commits moves, the
  right stick highlights and commits commands -- deflect to highlight,
  release to commit.
- Action queueing: while the foe is still acting, the same compass queues
  the next action, cooldown spinners orbit the move slots, and the pick
  fires the instant the menu returns -- dissolving quietly if the situation
  changed (faint, disable, empty PP, forced switch).
- Pad-matched button glyphs: Xbox letters, PlayStation shapes or Nintendo
  letters, chosen by live controller detection (name, then SDL GUID vendor
  id) with an OPTIONS override.
- Modern window-space skins for the battle bag, the battle party screen and
  the battle message box, painted over unmodified vanilla logic.
- Four OPTIONS rows: BATTLEPAD, QUICK MOVES, QUEUE NEXT, PAD ICONS -- the
  same settings the mod manager shows, stored in the engine's own options.
- A headless test suite covering compass math, queue validation, brand
  detection, option cycling and the input funnel's forward-when-unclaimed
  guarantee.

### Notes

- Safari Zone, the old-man demo and Mimic's copy menu keep the classic UI
  on purpose.
- Declared incompatible with USEFUL_BATTLE_CAM: both mods want the sticks
  during battle, and the loader now enforces the choice.
