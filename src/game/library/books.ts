import type { BookRow, GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'

export function bookById(db: GameDatabase, bookId: string): BookRow | undefined {
  return db.Books.find((row) => row['Book ID'] === bookId)
}

export function isBookUnlocked(save: PlayerSave, bookId: string): boolean {
  return (save.unlockedBookIds ?? []).includes(bookId)
}

/**
 * Unlock a book into the Library (idempotent). Books never enter the bag.
 */
export function grantBook(
  save: PlayerSave,
  bookId: string,
): { save: PlayerSave; granted: boolean; isFirstEver: boolean } {
  const unlocked = save.unlockedBookIds ?? []
  if (unlocked.includes(bookId)) {
    return { save, granted: false, isFirstEver: false }
  }
  return {
    save: { ...save, unlockedBookIds: [...unlocked, bookId] },
    granted: true,
    isFirstEver: unlocked.length === 0,
  }
}

export interface BookUnlockNotice {
  bookId: string
  name: string
  hint: string | null
}

export const LIBRARY_HINT = 'Open Library from the menu to read your books anytime.'

export function bookUnlockNotice(
  db: GameDatabase,
  bookId: string,
  isFirstEver: boolean,
): BookUnlockNotice | null {
  const book = bookById(db, bookId)
  if (!book) return null
  return {
    bookId,
    name: book['Display Name'],
    hint: isFirstEver ? LIBRARY_HINT : null,
  }
}

export function libraryBookRows(db: GameDatabase, save: PlayerSave): BookRow[] {
  const unlocked = new Set(save.unlockedBookIds ?? [])
  return db.Books.filter((row) => unlocked.has(row['Book ID'])).sort((a, b) =>
    a['Display Name'].localeCompare(b['Display Name']),
  )
}
