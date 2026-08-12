export type BazaarPostKind = 'message' | 'recruit' | 'trade'

export interface BazaarPost {
  id: string
  kind: BazaarPostKind
  userId: string
  username: string
  body: string
  createdAt: string
}
