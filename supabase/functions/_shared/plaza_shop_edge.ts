// Hosted plaza shop buy: refuse before the RPC, and pass pointsSpent through
// from plaza_shop_purchase_hosted. Kept free of Deno and supabase-js so the
// test suite can drive it with a fake admin whose rpc records calls.

export const PLAZA_SHOP_PURCHASE_RPC = 'plaza_shop_purchase_hosted'
export const PLAZA_SHOP_MISSING_ITEM = 'Missing item.'
export const PLAZA_SHOP_PURCHASE_FAILED = 'The plaza shop could not complete that purchase.'

export type PlazaRpcResult = { data: unknown; error: { message: string } | null }

export type PlazaRpcAdmin = {
  // supabase-js returns a thenable filter builder, not a Promise.
  rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<PlazaRpcResult>
}

export type PlazaAuthorityResult = { ok: true; save: unknown } | { ok: false; reason: string }

export type PlazaShopBuySettlement =
  | { kind: 'refused'; reason: string }
  | { kind: 'failed'; error: string; status: number; conflict?: boolean }
  | { kind: 'purchased'; version: number; save: unknown; plazaPoints: number; pointsSpent: number }

export function plazaShopBuyResponseExtras(
  purchased: Extract<PlazaShopBuySettlement, { kind: 'purchased' }>,
): { pointsGained: 0; plazaPoints: number; pointsSpent: number } {
  return {
    pointsGained: 0,
    plazaPoints: purchased.plazaPoints,
    pointsSpent: purchased.pointsSpent,
  }
}

/**
 * The game edge function's plaza_shop_buy step after applyGameCommand.
 * A refused command never calls plaza_shop_purchase_hosted.
 */
export async function settlePlazaShopBuyCommand(options: {
  commandResult: PlazaAuthorityResult
  admin: PlazaRpcAdmin
  userId: string
  args: Record<string, unknown>
  expectedVersion: number
  rngState: number
  nowMs: number
}): Promise<PlazaShopBuySettlement> {
  if (!options.commandResult.ok) {
    return { kind: 'refused', reason: options.commandResult.reason }
  }
  return settlePlazaShopPurchase(
    options.admin,
    options.userId,
    options.args,
    options.commandResult.save,
    options.expectedVersion,
    options.rngState,
    options.nowMs,
  )
}

export async function settlePlazaShopPurchase(
  admin: PlazaRpcAdmin,
  userId: string,
  args: Record<string, unknown>,
  preparedSave: unknown,
  expectedVersion: number,
  rngState: number,
  nowMs: number,
): Promise<PlazaShopBuySettlement> {
  const itemId = asTrimmedString(args.itemId)
  if (!itemId) return { kind: 'failed', error: PLAZA_SHOP_MISSING_ITEM, status: 400 }
  const { data, error } = await admin.rpc(PLAZA_SHOP_PURCHASE_RPC, {
    p_user_id: userId,
    p_item_id: itemId,
    p_expected_version: expectedVersion,
    p_payload: preparedSave,
    p_rng_state: rngState,
    p_now: new Date(nowMs).toISOString(),
  })
  if (error) return { kind: 'failed', error: error.message, status: 400 }
  const answer = (data ?? {}) as {
    ok?: boolean
    reason?: string
    conflict?: boolean
    version?: number
    plazaPoints?: number
    pointsSpent?: number
    payload?: unknown
  }
  if (answer.ok !== true) {
    return {
      kind: 'failed',
      error: answer.reason ?? PLAZA_SHOP_PURCHASE_FAILED,
      status: answer.conflict ? 409 : 400,
      conflict: answer.conflict,
    }
  }
  return {
    kind: 'purchased',
    version: Number(answer.version ?? expectedVersion + 1),
    save: answer.payload ?? preparedSave,
    plazaPoints: Number(answer.plazaPoints ?? 0),
    pointsSpent: Number(answer.pointsSpent ?? 0),
  }
}

function asTrimmedString(value: unknown): string | null {
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : null
}
