import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'game_popup.dart';
import 'ingredient_chip.dart';
import 'item_icon.dart';
import 'quantity_sheet.dart';
import 'recipe_book_sheet.dart';

/// The workshop counter as its own floating card, not in the location list.
Future<void> showProductionPicker(
  BuildContext context, {
  required GameController controller,
  required ActivityRow activity,
  Rect? origin,
}) {
  return showGamePopup<void>(
    context: context,
    origin: origin,
    builder: (context) => SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: ProductionPicker(
          controller: controller,
          activity: activity,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    ),
  );
}

/// The workshop counter: choose a recipe, choose how many, start the queue.
///
/// A queue is capped twice over — by the materials on hand and by the 24 hours
/// of work a queue may hold — so both ceilings are shown rather than letting a
/// number be typed that the rules would quietly cut down.
class ProductionPicker extends StatefulWidget {
  const ProductionPicker({
    super.key,
    required this.controller,
    required this.activity,
    this.onClose,
  });

  final GameController controller;
  final ActivityRow activity;
  final VoidCallback? onClose;

  @override
  State<ProductionPicker> createState() => _ProductionPickerState();
}

class _ProductionPickerState extends State<ProductionPicker> {
  String? _recipeId;
  num _quantity = 1;
  String? _error;

  GameController get controller => widget.controller;
  GameDatabase get db => controller.db;
  PlayerSave get save => controller.save;

  void _start(RecipeRow recipe, num quantity) {
    final result = requestProductionStart(
      db,
      save,
      widget.activity.activityId,
      recipe.recipeId,
      quantity,
      controller.session.clock(),
    );
    if (!result.ok) {
      setState(() => _error = result.reason);
      return;
    }
    controller.commit(result.save!);
    widget.onClose?.call();
  }

  void _openBook() {
    showStationRecipeBook(
      context,
      title: widget.activity.contextualName ?? widget.activity.internalKey,
      entries: recipeBookForActivity(save, db, widget.activity.activityId),
      db: db,
    );
  }

  @override
  Widget build(BuildContext context) {
    final known = recipesForActivity(db, save, widget.activity.activityId);
    final recipes = readyRecipesForActivity(db, save, widget.activity.activityId);
    final recipe =
        recipes.where((row) => row.recipeId == _recipeId).firstOrNull ?? recipes.firstOrNull;

    return GamePanel(
      framed: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.activity.contextualName ?? widget.activity.internalKey,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400),
                ),
              ),
              GameButton(
                label: 'Recipe book',
                tone: GameButtonTone.secondary,
                compact: true,
                onPressed: _openBook,
              ),
              if (widget.onClose != null) ...[
                const SizedBox(width: 6),
                GameIconButton(icon: Icons.close, tooltip: 'Close', onPressed: widget.onClose),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (recipe == null)
            MutedText(
              known.isEmpty
                  ? 'No recipes yet. Raise the skill, or learn one from a book or a person.'
                  : 'No recipes you can make right now. Open the recipe book to see what you need.',
            )
          else ...[
            GamePanel(
              child: GameDropdown<String>(
                label: 'Recipe',
                value: recipe.recipeId,
                items: [
                  for (final row in recipes)
                    GameDropdownItem(
                      value: row.recipeId,
                      label: '${row.displayName} (Lv ${row.proficiencyLevel})',
                    ),
                ],
                onChanged: (value) => setState(() {
                  _recipeId = value;
                  _quantity = 1;
                  _error = null;
                }),
              ),
            ),
            const SizedBox(height: 10),
            _RecipeDetails(controller: controller, recipe: recipe),
            const SizedBox(height: 10),
            _queueRow(recipe),
          ],
          if (_error case final error?) ...[
            const SizedBox(height: 6),
            Text(error, style: const TextStyle(color: Palette.danger, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _queueRow(RecipeRow recipe) {
    final fromMaterials = maxCraftsFromMaterials(save, recipe);
    final fromQueueCap = maxCraftsFromQueueCap(db, recipe);
    final ceiling = clampProductionQuantity(db, save, recipe, 999999);
    final quantity = _quantity.clamp(1, ceiling < 1 ? 1 : ceiling);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MutedText(
          'Up to ${formatThousands(ceiling)} — materials ${formatThousands(fromMaterials)}, '
          'queue ${formatThousands(fromQueueCap)}',
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            GameButton(
              label: formatThousands(quantity),
              tone: GameButtonTone.secondary,
              compact: true,
              onPressed: ceiling < 1
                  ? null
                  : () async {
                      final chosen = await askQuantity(
                        context,
                        subtitle: 'Queue quantity',
                        title: recipe.displayName,
                        details: [
                          'Materials allow ${formatThousands(fromMaterials)}',
                          'The 24h queue allows ${formatThousands(fromQueueCap)}',
                        ],
                        confirmLabel: 'Set quantity',
                        initialValue: quantity.toInt(),
                        max: ceiling.toInt(),
                      );
                      if (chosen == null || !mounted) return;
                      setState(() => _quantity = chosen);
                    },
            ),
            const SizedBox(width: 8),
            GameButton(
              label: 'Max',
              tone: GameButtonTone.secondary,
              compact: true,
              onPressed: ceiling < 1 ? null : () => setState(() => _quantity = ceiling),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GameButton(
                label: 'Start queue',
                onPressed: ceiling < 1 || controller.isRecovering
                    ? null
                    : () => _start(recipe, quantity),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        MutedText(
          'Uses ${formatDurationSeconds(quantity * recipe.baseDurationSeconds)} of the 24h cap.',
        ),
      ],
    );
  }
}

class _RecipeDetails extends StatelessWidget {
  const _RecipeDetails({required this.controller, required this.recipe});

  final GameController controller;
  final RecipeRow recipe;

  @override
  Widget build(BuildContext context) {
    final output = controller.indexes.itemsById[recipe.outputItemId];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ItemIcon(item: output, size: 30),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${output?.displayName ?? recipe.displayName} ×${_outputQuantityLabel(recipe)}',
                    style: const TextStyle(fontWeight: FontWeight.w400),
                  ),
                  MutedText(
                    '${formatDurationSeconds(recipe.baseDurationSeconds)} · '
                    '${formatThousands(recipe.xpReward)} XP',
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final ingredient in recipeIngredients(recipe))
              IngredientChip(
                item: controller.indexes.itemsById[ingredient.itemId],
                need: ingredient.quantity,
                owned: inventoryCount(controller.save, ingredient.itemId),
              ),
          ],
        ),
      ],
    );
  }
}

String _outputQuantityLabel(RecipeRow recipe) {
  if (recipe.skillId == alchemySkillId) {
    return '1–${alchemyPotionOutputMax.toInt()}';
  }
  return '${recipe.outputQuantity}';
}
