import 'package:flutter/material.dart';

/// The palette the game is drawn in: wood boards, tan panels, gold and green.
///
/// Vari's green/gold rules (UI-07 / UI-06):
/// - Gold: currency amounts, rare/premium items, achievements and titles,
///   panel headings.
/// - Green: whatever is selected, plus success, affordable/claimable, progress
///   and XP bars, confirm buttons.
/// - Borders: plain wood/neutral by default (plain stone on the stone pack).
///   Selected = green rim, never gold. Gold rim only for rare/featured items.
/// - Body text stays parchment; gold text only for amounts and headings.
abstract final class Palette {
  static const parchmentText = Color(0xFFF4E7C8);
  static const parchment = Color(0xFF5C4027);
  static const parchmentDeep = Color(0xFF3D2A1A);

  /// Item links in chat. Light sky blue — readable on wood and stone boards,
  /// and distinct from parchment body text and default gold names.
  static const chatItemLink = Color(0xFF7CC8F0);

  /// Mid gold between antique brass and bright jewelry — amounts, rare rims,
  /// headings on dark boards.
  static const gold = Color(0xFFA7872D);
  static const goldHighlight = Color(0xFFBFA445);
  static const goldShade = Color(0xFF5A420E);

  /// Gold copy on tan / ash plates. Dark enough for ~4.5:1 on [panelTan].
  static const goldInk = Color(0xFF4A3608);

  /// Outer board / wood chrome.
  static const wood = Color(0xFF2A1C12);
  static const softGreen = Color(0xFF2E8B57);
  static const softGreenShade = Color(0xFF1F5E3B);

  /// Skills-page XP bars: the same hue as [softGreen], brighter.
  static const skillXp = Color(0xFF3EBE68);
  static const ink = Color(0xFF1F1610);
  static const danger = Color(0xFFC2603F);

  /// Secondary body text, the old client's `.muted`.
  static const muted = Color(0xFFCBB894);

  /// Muted copy on tan inner panels.
  static const panelMuted = Color(0xFF6B5338);

  /// Body ink on tan inner panels.
  static const panelInk = Color(0xFF2A1C12);

  /// Location and panel headings on dark boards.
  static const heading = Color(0xFFE8D090);

  /// Body copy on top of location art.
  static const overlayText = Color(0xFFF2E6C8);

  /// Danger and combat warnings, the old client's `.danger-note`.
  static const warning = Color(0xFFEFB07A);

  /// Default wood plate rim — not gold. Stone rims live on [UiChrome].
  static const border = Color(0xFF6A4A30);
  static const borderHighlight = Color(0xFF8B6A48);
  static const borderShade = Color(0xFF2A1C12);

  /// Selected rim — green, never gold. Same on wood and stone.
  static const borderSelected = softGreen;
  static const borderSelectedHighlight = skillXp;
  static const borderSelectedShade = softGreenShade;

  /// Currency amounts.
  static const currency = gold;

  /// Rare / premium items, achievements, titles.
  static const rare = gold;
  static const rareHighlight = goldHighlight;
  static const rareShade = goldShade;

  /// Success, affordable, claimable.
  static const success = softGreen;

  /// Progress and XP bars, wait spinners.
  static const progress = skillXp;

  /// Cream label on green confirm buttons.
  static const confirmLabel = Color(0xFFF4FFE8);

  /// Confirm / buy / claim / pay fill. Darker than [skillXp] so the cream
  /// label clears ~4.5:1. Same green on wood and stone.
  static const confirmFill = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF287A4C), Color(0xFF1F5E3B)],
  );

  static const confirmPressed = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1F5E3B), Color(0xFF16452B)],
  );

  /// Disabled confirm fill. Neutral grey on wood and stone — not faded green.
  static const confirmDisabledFill = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF6E6E6E), Color(0xFF4A4A4A)],
  );

  static const confirmDisabledLabel = Color(0xFFE8E6E0);

  /// Hairline wood used for panel edges. Prefer [UiChrome.edge] so stone packs
  /// swap to iron instead of brown.
  static const edge = Color(0x736A4A30);

  /// The behind-everything wash — dark wood base under the plank texture.
  static const shellGradient = LinearGradient(
    begin: Alignment(-0.6, -1),
    end: Alignment(0.6, 1),
    colors: [Color(0xFF1A120C), Color(0xFF2A1C12), Color(0xFF14100A)],
    stops: [0, 0.45, 1],
  );

  /// The frame the game is played inside — outer brown board.
  static const frameGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF3D2A1A), Color(0xFF2A1C12)],
  );

  /// Outer wood board (HUD, nav, shell chrome).
  static const board = wood;

  /// Tan inner fill for menus and content panels.
  static const panelTan = Color(0xFFC4A882);

  /// Opaque card fill for docks, tiles, and panels (tan inset).
  static const panel = panelTan;

  /// Recessed item-slot well on tan panels.
  static const slot = Color(0xFF3D2A1A);
}
