import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../theme.dart';
import 'format.dart';
import 'game_popup.dart';

/// Gold cost and current gold from the quest data — never hardcoded.
class BribeQuote {
  const BribeQuote({required this.goldCost, required this.goldOwned});

  final num goldCost;
  final num goldOwned;

  bool get canAfford => goldOwned >= goldCost;

  String get needGold => 'Need ${formatThousands(goldCost)} gold.';
}

/// Reads [BribeGold] from the quest's structured objectives.
BribeQuote? bribeQuoteFor(GameDatabase db, PlayerSave save, String questId) {
  final quest = getQuest(db, questId);
  if (quest == null) return null;
  final parsed = parseStructuredObjectives(quest);
  if (parsed.bribeGold <= 0) return null;
  return BribeQuote(goldCost: parsed.bribeGold, goldOwned: save.gold);
}

/// Confirm before [quest_bribe]. Nothing is committed until Pay.
Future<bool> showBribeConfirmPopup({
  required BuildContext context,
  required GameDatabase db,
  required PlayerSave save,
  required String questId,
}) async {
  final quote = bribeQuoteFor(db, save, questId);
  if (quote == null) return false;
  final result = await showGamePopup<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return GamePopupCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Pay the bribe?',
              style: TextStyle(fontSize: gamePopupTitleSize, fontWeight: FontWeight.w400),
            ),
            const SizedBox(height: 8),
            Text('${formatThousands(quote.goldCost)} gold'),
            Text('You have ${formatThousands(quote.goldOwned)} gold'),
            if (!quote.canAfford) ...[
              const SizedBox(height: 8),
              Text(
                quote.needGold,
                style: const TextStyle(color: Palette.danger, fontSize: GameFont.s),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                GameButton(
                  key: const Key('bribe-cancel'),
                  label: 'Cancel',
                  tone: GameButtonTone.secondary,
                  compact: true,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GameButton(
                    key: const Key('bribe-pay'),
                    label: 'Pay',
                    onPressed: quote.canAfford ? () => Navigator.of(context).pop(true) : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  return result ?? false;
}
