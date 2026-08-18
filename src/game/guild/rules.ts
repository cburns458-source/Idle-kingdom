/**
 * What a guild action means, with nowhere to store the answer.
 *
 * The create form asks these of every keystroke so it can say what is missing,
 * and a backend asks them again before it writes anything.
 */

import { GUILD_CREATE_GOLD_COST, type CreateGuildInput } from '../multiplayer/types'

export const GUILD_NAME_MAX_LENGTH = 28
export const GUILD_DESCRIPTION_MAX_LENGTH = 160
export const GUILD_APPLICATION_MESSAGE_MAX_LENGTH = 120

export function guildNameFromInput(raw: string): string {
  return raw.trim().slice(0, GUILD_NAME_MAX_LENGTH)
}

/** A tag as it is stored: letters only, upper case, at most four. */
export function guildTagFromInput(raw: string): string {
  return raw.replace(/[^a-zA-Z]/g, '').toUpperCase().slice(0, 4)
}

export function guildDescriptionFromInput(raw: string | null | undefined): string {
  return (raw ?? '').trim().slice(0, GUILD_DESCRIPTION_MAX_LENGTH)
}

export function guildApplicationMessage(raw: string): string {
  return raw.trim().slice(0, GUILD_APPLICATION_MESSAGE_MAX_LENGTH)
}

/** Why a guild cannot be founded from a name, a tag, and a purse. */
export function createGuildRefusalFor(
  name: string,
  tag: string,
  goldAvailable: number,
): string | null {
  if (guildNameFromInput(name).length < 3) return 'Guild name needs at least 3 characters.'
  const cleanTag = guildTagFromInput(tag)
  if (cleanTag.length < 2 || cleanTag.length > 4) return 'Guild tag must be 2–4 letters.'
  if (goldAvailable < GUILD_CREATE_GOLD_COST) {
    return `Creating a guild costs ${GUILD_CREATE_GOLD_COST} gold.`
  }
  return null
}

/** Why a guild cannot be founded, or null when it can. */
export function createGuildRefusal(input: CreateGuildInput, goldAvailable: number): string | null {
  return createGuildRefusalFor(input.name, input.tag, goldAvailable)
}
