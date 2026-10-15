import type { RandomFn } from '../activity/pools'
import { requestActivityStart, requestActivityStop, requestProductionStart } from '../activity/transition'
import { toggleFavoriteActivity } from '../activity/favorites'
import { eatEquippedFood, eatInventoryFood } from '../combat/food'
import { collectCritter } from '../critters/critters'
import { withRecalculatedVitals } from '../equipment/vitals'
import { applyAutoEquipProposal, proposeAutoEquipForActivity } from '../equipment/autoEquip'
import {
  applyDesiredLoadout,
  equipInventoryIndex,
  unequipSlot,
  type DesiredLoadoutSlot,
} from '../equipment/loadout'
import {
  applyEquipmentPreset,
  renameEquipmentPreset,
  saveActiveEquipmentPreset,
  setEquipmentPresetIcon,
} from '../equipment/presets'
import { donateToGuildHall, payGuildHallDebt, withdrawFromGuildHall, type GuildHallState } from '../guild/economy'
import { canPayGuildDebt } from '../guild/hall'
import { depositToBank, withdrawFromBank } from '../inventory/bank'
import type { LootGrant } from '../activity/types'
import type { NoRoom } from '../inventory/fit'
import { sellInventoryIndexes, sellInventoryQuantities } from '../inventory/sell'
import { claimMailAttachments, markMailRead } from '../mail/mail'
import { confirmTannerJob } from '../npcs/tanner'
import {
  acceptQuestFromNpc,
  assignQuestSkillXp,
  bribeForQuest,
  changeRaceWithNpc,
  chooseCombatForQuest,
  donateForQuestFromNpc,
  learnMentorProjects,
  takeMerchantTip,
  talkWithQuestNpc,
} from '../npcs/conversation'
import { completeSpecialProject } from '../projects/engine'
import { completeQuest, type QuestFailure } from '../quests/quests'
import { applyQuestAutoStartOnSeed, applyQuestInspectProgress } from '../quests/progress'
import { assignRace } from '../races/assignRace'
import { chooseReligion } from '../religion/chooseReligion'
import { equipCosmetic } from '../cosmetics/cosmetics'
import { createNewSave, parseSave } from '../save/saveStore'
import type { AttackStyle, PlayerSave, PlayerSettings } from '../save/types'
import { CHARACTER_NAME_MAX_LENGTH, MOTTO_MAX_LENGTH } from '../save/types'
import { prepareDatabase } from '../data/loadDatabase'
import type { GameDatabase } from '../data/types'
import { createTrackedMulberry32 } from '../rng/mulberry32'
import { planTravel, planGuildHallTravel } from '../session/travel'
import { advanceSession } from '../session/tick'
import { confirmShopOffer, type ShopOffer } from '../shops/transactions'
import { resolveUnattendedProgress } from '../unattended/resolve'
import { requestBlessing } from '../world/blessing'
import { claimLocationSearch } from '../world/locationSearch'
import {
  collectLocationTimer,
  plantBestBotanySeed,
  plantBotanySeed,
  plantBotanySelection,
  placeTrap,
} from '../timers/locationTimers'
import { plazaPointsOf, purchasePlazaShopItem } from '../economy/plaza'
import { prepareBountyTurnIn, applyBountyReward } from '../bounties/reward'
import { syncBountyHour } from '../bounties/progress'
import { hourlyBountyBoard } from '../bounties/rotation'
import { simulatePvpFight, type PvpRoundResult } from '../combat/pvp'
import {
  applyRankedPvpResult,
  mintRankedFightId,
  RANKED_PVP_FAKED_WIN_REFUSAL,
  RANKED_PVP_UNKNOWN_FIGHT_REFUSAL,
  type ArenaOpponent,
} from '../pvp/matchmaking'
import { GUILD_CREATE_GOLD_COST } from '../multiplayer/types'
import { createGuildRefusalFor } from '../guild/rules'
import {
  chooseDialogue,
  startDialogue,
  viewDialogueNode,
  type DialogueItemDelta,
  type DialogueView,
} from '../dialogue/engine'
import type { QuestArrivalCompletion } from '../quests/quests'

export { createTrackedMulberry32 }

export type GameCommandName =
  | 'create_character'
  | 'set_meta'
  | 'travel'
  | 'travel_guild_hall'
  | 'start_activity'
  | 'stop_activity'
  | 'start_production'
  | 'confirm_auto_equip'
  | 'receive_blessing'
  | 'toggle_favorite'
  | 'eat_food'
  | 'set_combat_settings'
  | 'choose_quest_combat'
  | 'plant_botany'
  | 'plant_botany_selection'
  | 'plant_best_botany'
  | 'place_trap'
  | 'collect_timer'
  | 'collect_critter'
  | 'claim_location_search'
  | 'shop_confirm'
  | 'sell_inventory'
  | 'tanner_confirm'
  | 'equip_index'
  | 'unequip_slot'
  | 'set_loadout'
  | 'bank_deposit'
  | 'bank_withdraw'
  | 'equipment_preset_save'
  | 'equipment_preset_apply'
  | 'equipment_preset_edit'
  | 'quest_accept'
  | 'quest_donate'
  | 'quest_talk'
  | 'quest_learn'
  | 'quest_bribe'
  | 'quest_complete'
  | 'quest_assign_skill_xp'
  | 'merchant_tip_claim'
  | 'dialogue_choose'
  | 'dialogue_view'
  | 'quest_abandon'
  | 'quest_inspect'
  | 'quest_autostart_seed'
  | 'complete_special_project'
  | 'mail_read'
  | 'mail_claim'
  | 'sync_bounty_hour'
  | 'apply_ranked_pvp'
  | 'ranked_pvp_fight'
  | 'bounty_turn_in'
  | 'plaza_shop_buy'
  | 'change_race'
  | 'choose_religion'
  | 'guild_create'
  | 'guild_create_pay'
  | 'guild_pay_hall_debt'
  | 'guild_donate_hall_item'
  | 'guild_withdraw_hall_item'
  | 'submit_leaderboard'
  | 'save_pvp_equipment'

export type GameCommandArgs = Record<string, unknown>

export type ExistingRankedFight = {
  fightId: string
  outcome: 'win' | 'loss'
  goldGained: number
  pointsGained: number
  code?: string
  winsRemaining?: number
  rounds: PvpRoundResult[]
  youMaxHp: number
  themMaxHp: number
  opponent?: ArenaOpponent
}

export type GameCommandContext = {
  nowMs: number
  random: RandomFn
  hall?: GuildHallState
  userId?: string
  guildRole?: string
  opponentSave?: PlayerSave
  opponent?: ArenaOpponent
  issuedFightId?: string
  existingRankedFight?: ExistingRankedFight
}

export type GameCommandResult =
  | {
      ok: true
      save: PlayerSave
      hall?: GuildHallState
      goldCost?: number
      view?: DialogueView | null
      questCompletions?: QuestArrivalCompletion[]
      fightId?: string
      rounds?: PvpRoundResult[]
      pvpOutcome?: 'win' | 'loss'
      goldGained?: number
      pointsGained?: number
      plazaPoints?: number
      pointsSpent?: number
      code?: string
      winsRemaining?: number
      youMaxHp?: number
      themMaxHp?: number
      opponent?: ArenaOpponent
      firstCompleter?: boolean
      bountyId?: string
    }
  | { ok: false; reason: string }
  | { ok: false; reason: string; code: string; favourites?: DialogueItemDelta[]; noRoom?: NoRoom }
  | { ok: false; reason: string; catchingUp: true; save: PlayerSave }

export type Phase2SyncResult = {
  save: PlayerSave
  rngState: number
  gatheringActions: number
  craftsCompleted: number
  combatVictories: number
  combatDeaths: number
  effectiveElapsedMs: number
  caughtUp: boolean
  leftBehind?: LootGrant[]
}

/**
 * Wall-clock share of one `game` request the catch-up loop may spend. The edge
 * runtime kills a request at about two seconds of CPU and writes nothing, so
 * the loop stops well short and leaves room to load and write the save.
 */
export const HOSTED_CATCH_UP_BUDGET_MS = 600

export const CATCHING_UP_REASON = 'Still catching up your time away. Try again in a moment.'

/** Same copy as `bazaarBoundItem` in `packages/ik_net/lib/src/market.dart`. */
export const UNTRADEABLE_ITEM_REFUSAL = "That stays with you; it can't be traded."

/** False when the Items `Tradeable` column is false. Missing or blank means true. */
export function isItemTradeable(db: GameDatabase, itemId: string): boolean {
  return db.Items.find((row) => row['Item ID'] === itemId)?.Tradeable !== false
}

export type HostedCatchUpOptions = {
  /** Start of the unattended cap window when a previous request stopped early. */
  windowStartMs?: number
  budgetMs?: number
}

function asString(value: unknown): string | null {
  return typeof value === 'string' && value.trim().length > 0 ? value : null
}

function asNumber(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}

function asInt(value: unknown): number | null {
  const n = asNumber(value)
  return n == null ? null : Math.trunc(n)
}

function asBool(value: unknown, fallback = false): boolean {
  return typeof value === 'boolean' ? value : fallback
}

type StackIdentity = { itemId: string; enchantmentId?: string | null }

/** Present enchantment argument, or undefined when the client did not send one. */
function enchantmentArg(args: GameCommandArgs): string | null | undefined {
  if (!Object.prototype.hasOwnProperty.call(args, 'enchantmentId')) return undefined
  const value = args.enchantmentId
  return typeof value === 'string' && value.length > 0 ? value : null
}

function stackMatches(
  stack: StackIdentity | undefined,
  itemId: string,
  enchantmentId: string | null | undefined,
): boolean {
  if (!stack || stack.itemId !== itemId) return false
  if (enchantmentId === undefined) return true
  return (stack.enchantmentId ?? null) === enchantmentId
}

/**
 * Keep [index] when that stack is the named item. Otherwise find the item.
 * Older clients omit [itemId] and keep the index they tapped.
 */
function resolveStackIndex(
  stacks: StackIdentity[],
  index: number | null,
  itemId: string | null,
  enchantmentId: string | null | undefined,
): number | null {
  if (itemId == null) return index
  if (index != null && stackMatches(stacks[index], itemId, enchantmentId)) return index
  const found = stacks.findIndex((stack) => stackMatches(stack, itemId, enchantmentId))
  return found >= 0 ? found : null
}

function parseDesiredSlots(value: unknown): DesiredLoadoutSlot[] | null {
  if (!Array.isArray(value)) return null
  const slots: DesiredLoadoutSlot[] = []
  for (const entry of value) {
    if (!entry || typeof entry !== 'object') return null
    const row = entry as Record<string, unknown>
    const slotId = asString(row.slotId)
    const itemId = asString(row.itemId)
    const quantity = asInt(row.quantity)
    if (!slotId || !itemId || quantity == null || quantity <= 0) return null
    const enchantment =
      typeof row.enchantmentId === 'string' && row.enchantmentId.length > 0 ? row.enchantmentId : null
    slots.push({
      slotId,
      itemId,
      quantity,
      enchantmentId: enchantment,
      favorite: row.favorite === true,
    })
  }
  return slots
}

function failed(reason: string): GameCommandResult {
  return { ok: false, reason }
}

function ok(
  save: PlayerSave,
  extra?: Omit<Extract<GameCommandResult, { ok: true }>, 'ok' | 'save'>,
): GameCommandResult {
  return { ok: true, save, ...extra }
}

function unwrap<
  T extends
    | { ok: true; save: PlayerSave }
    | { ok: false; reason: string; code?: string; noRoom?: NoRoom },
>(result: T): GameCommandResult {
  if (result.ok) return ok(result.save)
  if (result.code) {
    return {
      ok: false,
      reason: result.reason,
      code: result.code,
      ...(result.noRoom ? { noRoom: result.noRoom } : {}),
    }
  }
  return failed(result.reason)
}

/** Like [unwrap], but keeps a quest refusal's code (`no_room`, `confirm_favourites`) and its data. */
function unwrapQuest(result: { ok: true; save: PlayerSave } | QuestFailure): GameCommandResult {
  if (result.ok) return ok(result.save)
  if (!result.code) return failed(result.reason)
  return {
    ok: false,
    reason: result.reason,
    code: result.code,
    ...(result.favourites ? { favourites: result.favourites } : {}),
    ...(result.noRoom ? { noRoom: result.noRoom } : {}),
  }
}

/** `useFavourites` is per request only: never written to the save, so a yes cannot carry over. */
function parseUseFavourites(args: GameCommandArgs): { ok: true; value: boolean } | { ok: false } {
  const raw = args.useFavourites
  if (raw !== undefined && typeof raw !== 'boolean') return { ok: false }
  return { ok: true, value: raw === true }
}

export function runPhase2Sync(
  rawDatabase: unknown,
  options: { save: unknown; nowMs: number; rngState: number } & HostedCatchUpOptions,
): Phase2SyncResult {
  const { launch: db } = prepareDatabase(rawDatabase)
  const tracked = createTrackedMulberry32(options.rngState)
  const current = parseSave(options.save, options.nowMs)
  const unattended = resolveUnattendedProgress(db, current, options.nowMs, tracked.random, {
    budgetMs: options.budgetMs ?? HOSTED_CATCH_UP_BUDGET_MS,
    windowStartMs: options.windowStartMs,
  })
  const save = unattended.caughtUp
    ? advanceSession(db, unattended.save, options.nowMs, tracked.random).save
    : unattended.save
  return {
    save,
    rngState: tracked.getState(),
    gatheringActions: unattended.gatheringActions,
    craftsCompleted: unattended.craftsCompleted,
    combatVictories: unattended.combatVictories,
    combatDeaths: unattended.combatDeaths,
    effectiveElapsedMs: unattended.effectiveElapsedMs,
    caughtUp: unattended.caughtUp,
    ...(unattended.leftBehind?.length ? { leftBehind: unattended.leftBehind } : {}),
  }
}

export function applyGameCommand(
  rawDatabase: unknown,
  options: {
    command: string
    args?: GameCommandArgs
    save?: unknown
  } & GameCommandContext &
    HostedCatchUpOptions,
): GameCommandResult {
  const { launch: db } = prepareDatabase(rawDatabase)
  const args = options.args ?? {}
  if (options.command === 'create_character') {
    return createCharacter(db, args, options.nowMs)
  }
  if (options.save === undefined) return failed('No cloud save.')
  const save = parseSave(options.save, options.nowMs)
  return applyExistingCommand(db, options.command, args, save, options)
}

function createCharacter(db: GameDatabase, args: GameCommandArgs, nowMs: number): GameCommandResult {
  const name = asString(args.name)?.trim() ?? ''
  if (name.length < 1 || name.length > CHARACTER_NAME_MAX_LENGTH) {
    return failed('Enter a character name.')
  }
  const raceId = asString(args.raceId)
  if (!raceId) return failed('Choose a race.')
  let save: PlayerSave = { ...createNewSave(db, nowMs), characterName: name }
  const assigned = assignRace(db, save, raceId)
  if (!assigned.ok) return failed(assigned.reason)
  save = { ...assigned.save, characterName: name }
  if (args.appearance && typeof args.appearance === 'object') {
    save = { ...save, appearance: { ...save.appearance, ...(args.appearance as Record<string, string>) } }
  }
  return ok(save)
}

function applyExistingCommand(
  db: GameDatabase,
  command: string,
  args: GameCommandArgs,
  save: PlayerSave,
  options: GameCommandContext & HostedCatchUpOptions,
): GameCommandResult {
  const nowMs = options.nowMs
  const random = options.random
  // Catch the hosted copy up before the intent so a sell/bank sees loot the
  // client already gathered, and the returned action clock is "now".
  const unattended = resolveUnattendedProgress(db, save, nowMs, random, {
    budgetMs: options.budgetMs ?? HOSTED_CATCH_UP_BUDGET_MS,
    windowStartMs: options.windowStartMs,
  })
  // An intent on a half-caught-up save would act on the wrong bag and clock.
  // The partial progress is still written so the retry continues from it.
  if (!unattended.caughtUp) {
    return { ok: false, reason: CATCHING_UP_REASON, catchingUp: true, save: unattended.save }
  }
  save = advanceSession(db, unattended.save, nowMs, random).save

  switch (command) {
    case 'set_meta':
      return applyMeta(db, save, args)
    case 'travel': {
      const destinationId = asString(args.destinationId)
      const browseMapId = asString(args.browseMapId) ?? destinationId
      if (!destinationId || !browseMapId) return failed('Missing destination.')
      const plan = planTravel(db, save, destinationId, browseMapId, nowMs, random)
      if (plan.kind === 'blocked') return failed('You cannot travel there.')
      return ok(plan.arrival.save)
    }
    case 'travel_guild_hall': {
      const plan = planGuildHallTravel(db, save, nowMs, random)
      if (plan.kind === 'blocked') return failed('You cannot travel there.')
      return ok(plan.arrival.save)
    }
    case 'start_activity':
    case 'confirm_auto_equip': {
      const activityId = asString(args.activityId)
      if (!activityId) return failed('Missing activity.')
      const allowAutoEquip = command === 'confirm_auto_equip' || asBool(args.allowAutoEquip, true)
      const started = requestActivityStart(db, save, activityId, nowMs, random)
      if (started.ok) return ok(started.save)
      if (allowAutoEquip) {
        const proposal = proposeAutoEquipForActivity(db, save, activityId, started.reason)
        if (proposal) {
          const equipped = applyAutoEquipProposal(db, save, proposal)
          if (equipped.ok) {
            const again = requestActivityStart(db, equipped.save, activityId, nowMs, random)
            if (again.ok) return ok(withRecalculatedVitals(db, again.save))
          }
        }
      }
      return failed(started.reason)
    }
    case 'stop_activity':
      return unwrap(requestActivityStop(db, save, nowMs))
    case 'start_production': {
      const activityId = asString(args.activityId)
      const recipeId = asString(args.recipeId)
      const quantity = asInt(args.quantity)
      if (!activityId || !recipeId || quantity == null) return failed('Missing production.')
      return unwrap(requestProductionStart(db, save, activityId, recipeId, quantity, nowMs))
    }
    case 'receive_blessing':
      return unwrap(requestBlessing(db, save, nowMs))
    case 'toggle_favorite': {
      const activityId = asString(args.activityId)
      if (!activityId) return failed('Missing activity.')
      return ok(toggleFavoriteActivity(save, save.currentLocationId, activityId))
    }
    case 'eat_food': {
      const index = asInt(args.inventoryIndex)
      const itemId = asString(args.itemId)
      if (index == null && itemId == null) return unwrap(eatEquippedFood(db, save))
      const resolved = resolveStackIndex(save.inventory, index, itemId, enchantmentArg(args))
      if (resolved == null) return failed('Nothing to eat.')
      return unwrap(eatInventoryFood(db, save, resolved))
    }
    case 'set_combat_settings':
      return ok(applyCombatSettings(save, args))
    case 'choose_quest_combat': {
      const questId = asString(args.questId)
      if (!questId) return failed('Missing quest.')
      return unwrap(chooseCombatForQuest(db, save, questId, nowMs, random))
    }
    case 'plant_botany': {
      const seedItemId = asString(args.seedItemId)
      if (!seedItemId) return failed('Missing seed.')
      return unwrap(plantBotanySeed(db, save, seedItemId, nowMs, asNumber(args.plantQuantity) ?? 3))
    }
    case 'plant_botany_selection': {
      const seedItemIds = Array.isArray(args.seedItemIds) ? args.seedItemIds.filter((id): id is string => typeof id === 'string') : []
      return unwrap(plantBotanySelection(db, save, seedItemIds, nowMs, asBool(args.usedCompost)))
    }
    case 'plant_best_botany':
      return unwrap(plantBestBotanySeed(db, save, nowMs))
    case 'place_trap': {
      const trapItemId = asString(args.trapItemId)
      if (!trapItemId) return failed('Missing trap.')
      const baitItemIds = Array.isArray(args.baitItemIds)
        ? args.baitItemIds.filter((id): id is string => typeof id === 'string')
        : []
      return unwrap(placeTrap(db, save, trapItemId, nowMs, baitItemIds))
    }
    case 'collect_timer': {
      const locationId = asString(args.locationId) ?? save.currentLocationId
      const kind = asString(args.kind)
      if (!kind) return failed('Missing timer.')
      return unwrap(collectLocationTimer(db, save, locationId, kind, nowMs, random))
    }
    case 'collect_critter':
      return unwrap(collectCritter(save, save.currentLocationId))
    case 'claim_location_search': {
      const searchId = asString(args.searchId)
      if (!searchId) return failed('Missing search.')
      const claimed = claimLocationSearch(db, save, searchId, nowMs)
      return claimed.ok ? ok(claimed.save) : failed(claimed.reason ?? 'Could not claim search.')
    }
    case 'shop_confirm': {
      const shopId = asString(args.shopId)
      if (!shopId) return failed('Missing shop.')
      const offer = args.offer as ShopOffer | undefined
      if (!offer) return failed('Missing offer.')
      return unwrap(confirmShopOffer(db, save, shopId, offer, nowMs))
    }
    case 'sell_inventory': {
      if (args.quantities && typeof args.quantities === 'object' && !Array.isArray(args.quantities)) {
        const quantities: Record<number, number> = {}
        for (const [key, value] of Object.entries(args.quantities as Record<string, unknown>)) {
          if (typeof value === 'number') quantities[Number(key)] = value
        }
        return unwrap(sellInventoryQuantities(db, save, quantities))
      }
      const indexes = Array.isArray(args.indexes)
        ? args.indexes.filter((value): value is number => typeof value === 'number')
        : []
      return unwrap(sellInventoryIndexes(db, save, indexes))
    }
    case 'tanner_confirm': {
      const npcId = asString(args.npcId)
      if (!npcId) return failed('Missing tanner.')
      const npc = db.NPCs.find((row) => row['NPC ID'] === npcId)
      if (!npc) return failed('Missing tanner.')
      const quantities = args.quantities
      if (!quantities || typeof quantities !== 'object') return failed('Missing hides.')
      return unwrap(confirmTannerJob(db, save, npc, quantities as Record<string, number>))
    }
    case 'equip_index': {
      const index = asInt(args.inventoryIndex)
      if (index == null) return failed('Missing item.')
      return unwrap(equipInventoryIndex(db, save, index))
    }
    case 'unequip_slot': {
      const slotId = asString(args.slotId)
      if (!slotId) return failed('Missing slot.')
      return unwrap(unequipSlot(save, slotId))
    }
    case 'set_loadout': {
      const slots = parseDesiredSlots(args.slots)
      if (slots == null) return failed('Missing loadout.')
      const applied = applyDesiredLoadout(db, save, slots, asInt(args.activeEquipmentPresetIndex))
      if (!applied.ok) return failed(applied.reason)
      return ok(withRecalculatedVitals(db, applied.save))
    }
    case 'bank_deposit': {
      const index = asInt(args.inventoryIndex)
      const quantity = asNumber(args.quantity)
      if (index == null || quantity == null) return failed('Missing deposit.')
      const resolved = resolveStackIndex(save.inventory, index, asString(args.itemId), enchantmentArg(args))
      if (resolved == null) return failed('That stack is not there.')
      return unwrap(depositToBank(save, resolved, quantity))
    }
    case 'bank_withdraw': {
      const index = asInt(args.bankIndex)
      const quantity = asNumber(args.quantity)
      if (index == null || quantity == null) return failed('Missing withdraw.')
      const resolved = resolveStackIndex(save.bank ?? [], index, asString(args.itemId), enchantmentArg(args))
      if (resolved == null) return failed('That stack is not there.')
      return unwrap(withdrawFromBank(save, resolved, quantity))
    }
    case 'equipment_preset_save':
      return ok(saveActiveEquipmentPreset(save))
    case 'equipment_preset_apply': {
      const index = asInt(args.presetIndex)
      if (index == null) return failed('Missing preset.')
      return unwrap(applyEquipmentPreset(db, save, index))
    }
    case 'equipment_preset_edit': {
      const index = asInt(args.presetIndex)
      if (index == null) return failed('Missing preset.')
      let next = save
      if (typeof args.name === 'string') next = renameEquipmentPreset(next, index, args.name)
      if (args.icon != null) next = setEquipmentPresetIcon(next, index, args.icon as never)
      return ok(next)
    }
    case 'quest_accept': {
      const questId = asString(args.questId)
      if (!questId) return failed('Missing quest.')
      return unwrap(acceptQuestFromNpc(db, save, questId))
    }
    case 'quest_donate': {
      const questId = asString(args.questId)
      if (!questId) return failed('Missing quest.')
      return unwrap(donateForQuestFromNpc(db, save, questId))
    }
    case 'quest_talk': {
      const npcId = asString(args.npcId)
      if (!npcId) return failed('Missing npc.')
      return unwrap(talkWithQuestNpc(db, save, npcId))
    }
    case 'quest_learn': {
      const npcId = asString(args.npcId)
      if (!npcId) return failed('Missing mentor.')
      return unwrap(learnMentorProjects(db, save, npcId))
    }
    case 'quest_bribe': {
      const questId = asString(args.questId)
      if (!questId) return failed('Missing quest.')
      return unwrapQuest(bribeForQuest(db, save, questId))
    }
    case 'quest_complete': {
      const questId = asString(args.questId)
      if (!questId) return failed('Missing quest.')
      const useFavourites = parseUseFavourites(args)
      if (!useFavourites.ok) return failed('useFavourites must be true or false.')
      return unwrapQuest(completeQuest(db, save, questId, { useFavourites: useFavourites.value }))
    }
    case 'quest_assign_skill_xp': {
      const skillId = asString(args.skillId)
      const amount = asNumber(args.amount)
      if (!skillId || amount == null) return failed('Missing skill.')
      return unwrap(assignQuestSkillXp(db, save, skillId, amount))
    }
    case 'merchant_tip_claim': {
      const npcId = asString(args.npcId)
      if (!npcId) return failed('Missing merchant.')
      const claimed = takeMerchantTip(db, save, npcId)
      return claimed ? ok(claimed.save) : ok(save)
    }
    case 'dialogue_choose': {
      const dialogueId = asString(args.dialogueId)
      const nodeId = asString(args.nodeId)
      const choiceId = asString(args.choiceId)
      if (!dialogueId || !nodeId || !choiceId) return failed('Missing dialogue choice.')
      const useFavourites = parseUseFavourites(args)
      if (!useFavourites.ok) return failed('useFavourites must be true or false.')
      const chosen = chooseDialogue(db, save, dialogueId, nodeId, choiceId, {
        useFavourites: useFavourites.value,
      })
      if (chosen.ok) return ok(chosen.save, { questCompletions: chosen.questCompletions })
      if (chosen.code === 'confirm_favourites') {
        return { ok: false, reason: chosen.reason, code: chosen.code, favourites: chosen.favourites }
      }
      if (chosen.code === 'no_room' && chosen.noRoom) {
        return { ok: false, reason: chosen.reason, code: chosen.code, noRoom: chosen.noRoom }
      }
      return failed(chosen.reason)
    }
    case 'dialogue_view': {
      // Read-only: the game function returns the view and does not write the save.
      const dialogueId = asString(args.dialogueId)
      if (!dialogueId) return failed('Missing dialogue.')
      const nodeId = asString(args.nodeId)
      if (nodeId) return ok(save, { view: viewDialogueNode(db, save, dialogueId, nodeId) })
      const started = startDialogue(db, save, dialogueId)
      return started.ok ? ok(save, { view: started.view }) : failed(started.reason)
    }
    case 'quest_abandon':
      return failed('Quests cannot be abandoned.')
    case 'quest_inspect': {
      const target = asString(args.target)
      if (!target) return failed('Missing inspect.')
      return ok(applyQuestInspectProgress(db, save, target))
    }
    case 'quest_autostart_seed':
      // Opening an NPC persists the seed-triggered quest start that
      // npcConversation otherwise applies to a copy only. Nothing else runs.
      return ok(applyQuestAutoStartOnSeed(db, save))
    case 'complete_special_project': {
      const projectId = asString(args.projectId)
      const quantity = asInt(args.quantity) ?? 1
      if (!projectId) return failed('Missing project.')
      return unwrap(
        completeSpecialProject(db, save, projectId, quantity, asString(args.enchantTargetId), nowMs),
      )
    }
    case 'mail_read': {
      const messageId = asString(args.messageId)
      if (!messageId) return failed('Missing mail.')
      return ok(markMailRead(save, messageId, nowMs))
    }
    case 'mail_claim': {
      const messageId = asString(args.messageId)
      if (!messageId) return failed('Missing mail.')
      return unwrap(claimMailAttachments(save, messageId, nowMs, db))
    }
    case 'sync_bounty_hour':
      return ok(syncBountyHour(save, nowMs))
    case 'apply_ranked_pvp':
      return failed(RANKED_PVP_FAKED_WIN_REFUSAL)
    case 'ranked_pvp_fight':
      return resolveRankedPvpFightCommand(db, save, args, options)
    case 'bounty_turn_in':
      return resolveBountyTurnInCommand(save, args, nowMs)
    case 'plaza_shop_buy':
      return resolvePlazaShopBuyCommand(db, save, args)
    case 'change_race': {
      const raceId = asString(args.raceId)
      if (!raceId) return failed('Missing race.')
      return unwrap(changeRaceWithNpc(db, save, raceId, nowMs))
    }
    case 'choose_religion': {
      const religionId = asString(args.religionId)
      if (!religionId) return failed('Missing faith.')
      const chosen = chooseReligion(db, save, religionId, nowMs)
      if (!chosen.ok) return failed(chosen.reason)
      return chosen.goldCost > 0 ? ok(chosen.save, { goldCost: chosen.goldCost }) : ok(chosen.save)
    }
    case 'guild_create':
    case 'guild_create_pay': {
      const refusal = createGuildRefusalFor(asString(args.name) ?? '', asString(args.tag) ?? '', save.gold)
      if (refusal) return failed(refusal)
      return ok({ ...save, gold: save.gold - GUILD_CREATE_GOLD_COST }, { goldCost: GUILD_CREATE_GOLD_COST })
    }
    case 'guild_pay_hall_debt': {
      if (!options.hall || !options.userId) return failed('Join a guild first.')
      if (options.guildRole && !canPayGuildDebt(options.guildRole)) {
        return failed('Recruits cannot pay the hall debt.')
      }
      const amount = asNumber(args.amount)
      if (amount == null) return failed('Choose an amount.')
      const paid = payGuildHallDebt(options.hall, options.userId, save, amount)
      return paid.ok ? ok(paid.save, { hall: paid.hall }) : failed(paid.reason)
    }
    case 'guild_donate_hall_item': {
      if (!options.hall) return failed('Join a guild first.')
      const index = asInt(args.inventoryIndex)
      const quantity = asNumber(args.quantity)
      if (index == null || quantity == null) return failed('Missing donation.')
      const resolved = resolveStackIndex(save.inventory, index, asString(args.itemId), enchantmentArg(args))
      if (resolved == null) return failed('That stack is not there.')
      // Officers can withdraw from the storehouse, so a donation can reach another player.
      if (!isItemTradeable(db, save.inventory[resolved].itemId)) return failed(UNTRADEABLE_ITEM_REFUSAL)
      const donated = donateToGuildHall(options.hall, save, resolved, quantity)
      return donated.ok ? ok(donated.save, { hall: donated.hall }) : failed(donated.reason)
    }
    case 'guild_withdraw_hall_item': {
      if (!options.hall) return failed('Join a guild first.')
      if (options.guildRole !== 'leader' && options.guildRole !== 'officer') {
        return failed('Officers or the leader can withdraw.')
      }
      const index = asInt(args.storehouseIndex)
      const quantity = asNumber(args.quantity)
      if (index == null || quantity == null) return failed('Missing withdraw.')
      const resolved = resolveStackIndex(
        options.hall.storehouse,
        index,
        asString(args.itemId),
        enchantmentArg(args),
      )
      if (resolved == null) return failed('That stack is not there.')
      const withdrawn = withdrawFromGuildHall(options.hall, save, resolved, quantity)
      return withdrawn.ok ? ok(withdrawn.save, { hall: withdrawn.hall }) : failed(withdrawn.reason)
    }
    case 'submit_leaderboard':
    case 'save_pvp_equipment':
      return ok(save)
    default:
      return failed('Unknown command.')
  }
}

function resolveRankedPvpFightCommand(
  db: GameDatabase,
  save: PlayerSave,
  args: GameCommandArgs,
  options: GameCommandContext,
): GameCommandResult {
  if (Object.prototype.hasOwnProperty.call(args, 'won')) {
    return failed(RANKED_PVP_FAKED_WIN_REFUSAL)
  }
  const requested = asString(args.fightId)
  const existing = options.existingRankedFight
  if (existing) {
    if (requested && requested !== existing.fightId) return failed(RANKED_PVP_UNKNOWN_FIGHT_REFUSAL)
    return ok(save, {
      fightId: existing.fightId,
      rounds: existing.rounds,
      pvpOutcome: existing.outcome,
      goldGained: 0,
      pointsGained: existing.pointsGained ?? 0,
      plazaPoints: plazaPointsOf(save),
      code: existing.code,
      winsRemaining: existing.winsRemaining,
      youMaxHp: existing.youMaxHp,
      themMaxHp: existing.themMaxHp,
      opponent: existing.opponent ?? options.opponent,
    })
  }
  if (requested) {
    if (!options.issuedFightId || requested !== options.issuedFightId) {
      return failed(RANKED_PVP_UNKNOWN_FIGHT_REFUSAL)
    }
  }
  if (!options.opponentSave) return failed('No other players to fight.')
  let opponentSave: PlayerSave
  try {
    opponentSave = parseSave(options.opponentSave, options.nowMs)
  } catch {
    return failed('No other players to fight.')
  }
  const fightId = options.issuedFightId ?? requested ?? mintRankedFightId()
  const fight = simulatePvpFight(db, save, opponentSave, options.random)
  const applied = applyRankedPvpResult(save, fight.outcome === 'win', options.nowMs)
  return ok(applied.save, {
    fightId,
    rounds: fight.rounds,
    pvpOutcome: fight.outcome,
    goldGained: 0,
    pointsGained: applied.pointsGained,
    plazaPoints: plazaPointsOf(applied.save),
    code: applied.code,
    winsRemaining: applied.winsRemaining,
    youMaxHp: fight.youMaxHp,
    themMaxHp: fight.themMaxHp,
    opponent: options.opponent,
  })
}

function resolveBountyTurnInCommand(
  save: PlayerSave,
  args: GameCommandArgs,
  nowMs: number,
): GameCommandResult {
  const bountyId = asString(args.bountyId)
  if (!bountyId) return failed('Missing bounty.')
  const bounty = hourlyBountyBoard(nowMs).bounties.find((row) => row.id === bountyId)
  if (!bounty) return failed('That bounty is not on the current board.')
  const prepared = prepareBountyTurnIn(save, bounty, nowMs)
  if (!prepared.ok) return failed(prepared.reason)
  if (typeof args.firstCompleter !== 'boolean') {
    return ok(prepared.save, { bountyId })
  }
  const rewarded = applyBountyReward(prepared.save, bounty, args.firstCompleter)
  return ok(rewarded.save, {
    goldGained: 0,
    pointsGained: rewarded.pointsGained,
    plazaPoints: plazaPointsOf(rewarded.save),
    firstCompleter: args.firstCompleter,
    bountyId,
  })
}

function resolvePlazaShopBuyCommand(
  db: GameDatabase,
  save: PlayerSave,
  args: GameCommandArgs,
): GameCommandResult {
  const itemId = asString(args.itemId)
  if (!itemId) return failed('Missing item.')
  const bought = purchasePlazaShopItem(db, save, itemId, args.points ?? args.amount ?? args.gold)
  if (!bought.ok) return failed(bought.reason)
  return ok(bought.save, {
    pointsGained: 0,
    plazaPoints: bought.plazaPoints,
    pointsSpent: bought.pointsSpent,
  })
}

function applyMeta(db: GameDatabase, save: PlayerSave, args: GameCommandArgs): GameCommandResult {
  let next = save
  if (typeof args.characterName === 'string') {
    const name = args.characterName.trim().slice(0, CHARACTER_NAME_MAX_LENGTH)
    if (name.length > 0) next = { ...next, characterName: name }
  }
  if (args.motto === null || typeof args.motto === 'string') {
    const motto = args.motto === null ? null : String(args.motto).trim().slice(0, MOTTO_MAX_LENGTH)
    next = { ...next, motto: motto === '' ? null : motto }
  }
  if (typeof args.hasSeenWardrobeIntro === 'boolean') {
    next = { ...next, hasSeenWardrobeIntro: args.hasSeenWardrobeIntro }
  }
  if (typeof args.hasSeenFennelIntro === 'boolean') {
    next = { ...next, hasSeenFennelIntro: args.hasSeenFennelIntro }
  }
  if (args.appearance && typeof args.appearance === 'object') {
    next = { ...next, appearance: { ...next.appearance, ...(args.appearance as PlayerSave['appearance']) } }
  }
  if (args.equippedCosmetics && typeof args.equippedCosmetics === 'object') {
    const equipped = args.equippedCosmetics as Record<string, unknown>
    let cosmeticsSave = next
    for (const [slotId, rawId] of Object.entries(equipped)) {
      const cosmeticId = typeof rawId === 'string' && rawId.length > 0 ? rawId : null
      const equippedSlot = equipCosmetic(db, cosmeticsSave, slotId, cosmeticId)
      if (!equippedSlot.ok) return failed(equippedSlot.reason)
      cosmeticsSave = equippedSlot.save
    }
    next = cosmeticsSave
  }
  if (typeof args.inventoryFavoriteIndex === 'number') {
    const index = Math.trunc(args.inventoryFavoriteIndex)
    if (index >= 0 && index < next.inventory.length) {
      const inventory = next.inventory.map((stack, at) =>
        at === index ? { ...stack, favorite: !stack.favorite } : stack,
      )
      next = { ...next, inventory }
    }
  }
  if (typeof args.equippedFavoriteSlotId === 'string') {
    const slotId = args.equippedFavoriteSlotId
    const current = next.equipment.slots[slotId]
    if (current) {
      next = {
        ...next,
        equipment: {
          ...next.equipment,
          slots: {
            ...next.equipment.slots,
            [slotId]: { ...current, favorite: !current.favorite },
          },
        },
      }
    }
  }
  if (args.settings && typeof args.settings === 'object') {
    next = { ...next, settings: { ...next.settings, ...(args.settings as PlayerSettings) } }
  }
  if (args.lootTrackers && typeof args.lootTrackers === 'object') {
    next = { ...next, lootTrackers: args.lootTrackers as PlayerSave['lootTrackers'] }
  }
  if (args.xpTrackers && typeof args.xpTrackers === 'object') {
    next = { ...next, xpTrackers: args.xpTrackers as PlayerSave['xpTrackers'] }
  }
  if (args.lootTrackerPausedAtMs === null || typeof args.lootTrackerPausedAtMs === 'number') {
    next = { ...next, lootTrackerPausedAtMs: args.lootTrackerPausedAtMs as number | null }
  }
  if (args.xpTrackerPausedAtMs === null || typeof args.xpTrackerPausedAtMs === 'number') {
    next = { ...next, xpTrackerPausedAtMs: args.xpTrackerPausedAtMs as number | null }
  }
  return ok(next)
}

function applyCombatSettings(save: PlayerSave, args: GameCommandArgs): PlayerSave {
  const styles: AttackStyle[] = ['offensive', 'defensive', 'balanced']
  const attackStyle = asString(args.attackStyle)
  return {
    ...save,
    attackStyle: styles.includes(attackStyle as AttackStyle) ? (attackStyle as AttackStyle) : save.attackStyle,
    settings: {
      ...save.settings,
      showEatButton: typeof args.showEatButton === 'boolean' ? args.showEatButton : save.settings.showEatButton,
      shareLocationWithFriends:
        typeof args.shareLocationWithFriends === 'boolean'
          ? args.shareLocationWithFriends
          : save.settings.shareLocationWithFriends,
      potionsPaused: typeof args.potionsPaused === 'boolean' ? args.potionsPaused : save.settings.potionsPaused,
      autoEat: typeof args.autoEat === 'boolean' ? args.autoEat : save.settings.autoEat,
      eatHealthThresholdPercent:
        typeof args.eatHealthThresholdPercent === 'number'
          ? args.eatHealthThresholdPercent
          : save.settings.eatHealthThresholdPercent,
      eatHealthThresholdAsPercent:
        typeof args.eatHealthThresholdAsPercent === 'boolean'
          ? args.eatHealthThresholdAsPercent
          : save.settings.eatHealthThresholdAsPercent,
      botanyUseCompost:
        typeof args.botanyUseCompost === 'boolean' ? args.botanyUseCompost : save.settings.botanyUseCompost,
    },
  }
}

