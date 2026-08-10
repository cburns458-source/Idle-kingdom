/** Parse a typed shop buy/sell quantity. Optional max clamps sellable remaining. */
export function parseShopQuantity(
  raw: string,
  max?: number,
): { ok: true; quantity: number } | { ok: false; reason: string } {
  const trimmed = raw.trim()
  if (!trimmed) return { ok: false, reason: 'Enter a quantity.' }
  if (!/^\d+$/.test(trimmed)) return { ok: false, reason: 'Enter a whole number.' }
  const quantity = Number(trimmed)
  if (!Number.isSafeInteger(quantity) || quantity < 1) {
    return { ok: false, reason: 'Quantity must be at least 1.' }
  }
  if (typeof max === 'number' && quantity > max) {
    return { ok: false, reason: max <= 0 ? 'Nothing left to sell.' : `You can sell at most ${max}.` }
  }
  return { ok: true, quantity }
}
