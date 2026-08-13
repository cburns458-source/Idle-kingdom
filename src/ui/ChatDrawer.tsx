import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from 'react'
import { getSession, isSignedIn } from '../game/multiplayer/auth'
import {
  countUnreadDirectMessages,
  listChatMessages,
  listDirectMessages,
  sendChatMessage,
} from '../game/multiplayer/chat'
import { currentGuildId } from '../game/multiplayer/guilds'
import type { ChatMessage } from '../game/multiplayer/types'
import {
  chatChannelForTab,
  chatLocalLocationId,
  chatTabs,
  emptyChatMessage,
  dmReadCursorKey,
  unreadBadgeLabel,
  CHAT_DM_HINT,
  CHAT_NO_GUILD_NOTICE,
  type ChatTab,
} from '../game/multiplayer/views'

interface ChatDrawerProps {
  locationId: string
  /** When true, Local chat uses the shared Citadel hub channel. */
  citadelHubChat?: boolean
}

const SHEET_MID = 0.5
const SHEET_FULL = 0.92
const DISMISS_BELOW = 0.28

function readDmCursor(userId: string): string | null {
  try {
    return localStorage.getItem(dmReadCursorKey(userId))
  } catch {
    return null
  }
}

function writeDmCursor(userId: string, iso: string): void {
  try {
    localStorage.setItem(dmReadCursorKey(userId), iso)
  } catch {
    /* ignore quota / private mode */
  }
}

function ChatBubbleIcon() {
  return (
    <svg className="chat-fab-icon" viewBox="0 0 24 24" aria-hidden>
      <path
        fill="currentColor"
        d="M4 3.5h16A2.5 2.5 0 0 1 22.5 6v9A2.5 2.5 0 0 1 20 17.5H11l-4.8 3.2c-.7.5-1.7 0-1.7-.9V17.5H4A2.5 2.5 0 0 1 1.5 15V6A2.5 2.5 0 0 1 4 3.5zm2.2 4.2v1.8h11.6V7.7zm0 3.6v1.8h8.2v-1.8z"
      />
    </svg>
  )
}

/** Non-blocking circular chat FAB + draggable bottom sheet. */
export function ChatDrawer({ locationId, citadelHubChat = false }: ChatDrawerProps) {
  const session = getSession()
  const [open, setOpen] = useState(false)
  const [channel, setChannel] = useState<ChatTab>('global')
  const [body, setBody] = useState('')
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [notice, setNotice] = useState<string | null>(null)
  const [unreadDms, setUnreadDms] = useState(0)
  const [sheetRatio, setSheetRatio] = useState(SHEET_MID)
  const guildId = currentGuildId()
  const sheetRatioRef = useRef(SHEET_MID)
  const dragRef = useRef<{
    startY: number
    startRatio: number
    pointerId: number
  } | null>(null)
  const sheetRef = useRef<HTMLDivElement | null>(null)
  const localLocationId = chatLocalLocationId(locationId, citadelHubChat)
  const tabs = chatTabs({
    selected: channel,
    citadelHub: citadelHubChat,
    hasGuild: guildId !== null,
    unreadDms,
  })
  const unreadBadge = unreadBadgeLabel(unreadDms)

  function setRatio(next: number) {
    sheetRatioRef.current = next
    setSheetRatio(next)
  }

  function refreshUnread() {
    if (!session) {
      setUnreadDms(0)
      return
    }
    setUnreadDms(countUnreadDirectMessages(readDmCursor(session.userId)))
  }

  function markDmsRead() {
    if (!session) return
    writeDmCursor(session.userId, new Date().toISOString())
    setUnreadDms(0)
  }

  useEffect(() => {
    if (!isSignedIn()) return
    refreshUnread()
    const timer = window.setInterval(refreshUnread, 4000)
    return () => window.clearInterval(timer)
  }, [session?.userId])

  useEffect(() => {
    if (!isSignedIn() || !open) return
    if (channel === 'dm') {
      void listDirectMessages().then((rows) => {
        setMessages(rows)
        markDmsRead()
      })
      return
    }
    const selected =
      chatChannelForTab(channel, { locationId, citadelHub: citadelHubChat, guildId }) ??
      ({ kind: 'global' } as const)
    void listChatMessages(selected).then(setMessages)
  }, [open, channel, localLocationId, guildId])

  useEffect(() => {
    if (!open) return
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') closeSheet()
    }
    document.addEventListener('keydown', onKeyDown)
    return () => document.removeEventListener('keydown', onKeyDown)
  }, [open])

  if (!isSignedIn() || !session) return null

  function openSheet() {
    setRatio(SHEET_MID)
    setOpen(true)
  }

  function closeSheet() {
    setOpen(false)
    setRatio(SHEET_MID)
    refreshUnread()
  }

  function onHandlePointerDown(event: ReactPointerEvent<HTMLDivElement>) {
    event.currentTarget.setPointerCapture(event.pointerId)
    dragRef.current = {
      startY: event.clientY,
      startRatio: sheetRatioRef.current,
      pointerId: event.pointerId,
    }
  }

  function onHandlePointerMove(event: ReactPointerEvent<HTMLDivElement>) {
    const drag = dragRef.current
    if (!drag || drag.pointerId !== event.pointerId) return
    const frame = sheetRef.current?.offsetParent as HTMLElement | null
    const frameHeight = frame?.clientHeight ?? window.innerHeight
    if (frameHeight <= 0) return
    const deltaRatio = (drag.startY - event.clientY) / frameHeight
    const next = Math.min(SHEET_FULL, Math.max(0.12, drag.startRatio + deltaRatio))
    setRatio(next)
  }

  function onHandlePointerUp(event: ReactPointerEvent<HTMLDivElement>) {
    const drag = dragRef.current
    if (!drag || drag.pointerId !== event.pointerId) return
    dragRef.current = null
    try {
      event.currentTarget.releasePointerCapture(event.pointerId)
    } catch {
      /* already released */
    }
    const current = sheetRatioRef.current
    if (current < DISMISS_BELOW) {
      closeSheet()
      return
    }
    const midDist = Math.abs(current - SHEET_MID)
    const fullDist = Math.abs(current - SHEET_FULL)
    setRatio(fullDist < midDist ? SHEET_FULL : SHEET_MID)
  }

  function activeChannel() {
    return chatChannelForTab(channel, { locationId, citadelHub: citadelHubChat, guildId })
  }

  return (
    <>
      {!open && (
        <div className="chat-fab-host">
          <button
            type="button"
            className="chat-fab"
            aria-label={unreadDms > 0 ? `Open chat, ${unreadDms} unread messages` : 'Open chat'}
            onClick={openSheet}
          >
            <ChatBubbleIcon />
            {unreadBadge && (
              <span className="chat-fab-badge" aria-hidden>
                {unreadBadge}
              </span>
            )}
          </button>
        </div>
      )}

      {open && (
        <>
          <button
            type="button"
            className="chat-sheet-backdrop"
            aria-label="Dismiss chat"
            onClick={closeSheet}
          />
          <div
            ref={sheetRef}
            className="chat-sheet"
            role="dialog"
            aria-label="Chat"
            style={{ height: `${Math.round(sheetRatio * 100)}%` }}
          >
            <div
              className="chat-sheet-handle"
              onPointerDown={onHandlePointerDown}
              onPointerMove={onHandlePointerMove}
              onPointerUp={onHandlePointerUp}
              onPointerCancel={onHandlePointerUp}
            >
              <span className="chat-sheet-handle-bar" />
            </div>
            <div className="chat-sheet-tabs menu-tabs" role="tablist" aria-label="Chat channels">
              {tabs.map((tab) => (
                <button
                  key={tab.tab}
                  type="button"
                  role="tab"
                  aria-selected={tab.selected}
                  className={tab.selected ? 'menu-tab active' : 'menu-tab'}
                  disabled={!tab.enabled}
                  onClick={() => setChannel(tab.tab)}
                >
                  {tab.label}
                </button>
              ))}
            </div>
            <ul className="chat-drawer-messages">
              {messages.map((message) => (
                <li key={message.id}>
                  <strong>{message.username}</strong> {message.body}
                </li>
              ))}
              {messages.length === 0 && (
                <li className="muted tiny">{emptyChatMessage(channel)}</li>
              )}
            </ul>
            {channel !== 'dm' && (
              <form
                className="chat-compose"
                onSubmit={(event) => {
                  event.preventDefault()
                  const selected = activeChannel()
                  if (!selected) {
                    setNotice(CHAT_NO_GUILD_NOTICE)
                    return
                  }
                  void sendChatMessage(selected, body).then((result) => {
                    if (!result.ok) {
                      setNotice(result.reason)
                      return
                    }
                    setBody('')
                    setNotice(null)
                    void listChatMessages(selected).then(setMessages)
                  })
                }}
              >
                <input
                  className="text-input"
                  value={body}
                  onChange={(event) => setBody(event.target.value)}
                  placeholder="Message…"
                  maxLength={240}
                  aria-label="Chat message"
                />
                <button type="submit" className="btn primary">
                  Send
                </button>
              </form>
            )}
            {channel === 'dm' && (
              <p className="muted tiny chat-dm-hint">{CHAT_DM_HINT}</p>
            )}
            {notice && <p className="muted tiny">{notice}</p>}
          </div>
        </>
      )}
    </>
  )
}
