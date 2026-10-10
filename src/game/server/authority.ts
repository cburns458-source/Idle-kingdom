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
import { completeQuest } from '../quests/quests'
import { applyQuestInspectProgress } from '../quests/progress'
import { assignRace } from '../races/assignRace'
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
import { syncBountyHour } from '../bounties/progress'
import { applyRankedPvpResult } from '../pvp/matchmaking'
import { GUILD_CREATE_GOLD_COST } from '../multiplayer/types'
import { createGuildRefusalFor } from '../guild/rules'

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
  | 'quest_inspect'
  | 'complete_special_project'
  | 'mail_read'
  | 'mail_claim'
  | 'sync_bounty_hour'
  | 'apply_ranked_pvp'
  | 'change_race'
  | 'guild_create'
  | 'guild_create_pay'
  | 'guild_pay_hall_debt'
  | 'guild_donate_hall_item'
  | 'guild_withdraw_hall_item'
  | 'submit_leaderboard'
  | 'save_pvp_equipment'

export type GameCommandArgs = Record<string, unknown>

export type GameCommandResult =
  | { ok: true; save: PlayerSave; hall?: GuildHallState; goldCost?: number }
  | { ok: false; reason: string }
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
}

/**
 * Wall-clock share of one `game` request the catch-up loop may spend. The edge
 * runtime kills a request at about two seconds of CPU and writes nothing, so
 * the loop stops well short and leaves room to load and write the save.
 */
export const HOSTED_CATCH_UP_BUDGET_MS = 600

export const CATCHING_UP_REASON = 'Still catching up your time away. Try again in a moment.'

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

function ok(save: PlayerSave, extra?: { hall?: GuildHallState; goldCost?: number }): GameCommandResult {
  return { ok: true, save, ...extra }
}

function unwrap<T extends { ok: true; save: PlayerSave } | { ok: false; reason: string }>(
  result: T,
): GameCommandResult {
  return result.ok ? ok(result.save) : failed(result.reason)
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
  }
}

export function applyGameCommand(
  rawDatabase: unknown,
  options: {
    command: string
    args?: GameCommandArgs
    save?: unknown
    nowMs: number
    random: RandomFn
    hall?: GuildHallState
    userId?: string
    guildRole?: string
  } & HostedCatchUpOptions,
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
  options: {
    nowMs: number
    random: RandomFn
    hall?: GuildHallState
    userId?: string
    guildRole?: string
  } & HostedCatchUpOptions,
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
      return ok(applyMeta(save, args))
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
      return unwrap(bribeForQuest(db, save, questId))
    }
    case 'quest_complete': {
      const questId = asString(args.questId)
      if (!questId) return failed('Missing quest.')
      return unwrap(completeQuest(db, save, questId))
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
    case 'quest_inspect': {
      const target = asString(args.target)
      if (!target) return failed('Missing inspect.')
      return ok(applyQuestInspectProgress(db, save, target))
    }
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
      return ok(applyRankedPvpResult(save, asBool(args.won), nowMs))
    case 'change_race': {
      const raceId = asString(args.raceId)
      if (!raceId) return failed('Missing race.')
      return unwrap(changeRaceWithNpc(db, save, raceId, nowMs))
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

function applyMeta(save: PlayerSave, args: GameCommandArgs): PlayerSave {
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
    next = {
      ...next,
      cosmetics: {
        ...next.cosmetics,
        equipped: args.equippedCosmetics as PlayerSave['cosmetics']['equipped'],
      },
    }
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
  return next
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

