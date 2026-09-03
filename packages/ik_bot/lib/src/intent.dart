/// One decision the bot makes after a tick.
sealed class BotIntent {
  const BotIntent();
}

/// Sit this tick: death pause, combat, or an activity already running.
class BotWait extends BotIntent {
  const BotWait([this.reason = 'wait']);

  final String reason;
}

class BotTravel extends BotIntent {
  const BotTravel(this.locationId);

  final String locationId;
}

class BotStartGather extends BotIntent {
  const BotStartGather(this.activityId);

  final String activityId;
}

class BotStartProduction extends BotIntent {
  const BotStartProduction(this.activityId, this.recipeId, this.quantity);

  final String activityId;
  final String recipeId;
  final num quantity;
}

class BotCompleteProject extends BotIntent {
  const BotCompleteProject(this.projectId);

  final String projectId;
}

class BotBuy extends BotIntent {
  const BotBuy(this.shopId, this.itemId);

  final String shopId;
  final String itemId;
}

class BotAcceptQuest extends BotIntent {
  const BotAcceptQuest(this.questId);

  final String questId;
}

class BotCompleteQuest extends BotIntent {
  const BotCompleteQuest(this.questId);

  final String questId;
}
