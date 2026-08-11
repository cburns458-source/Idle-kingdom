import { useEffect, useState } from 'react'
import { isSignedIn } from '../game/multiplayer/auth'
import { listChatMessages, sendChatMessage } from '../game/multiplayer/chat'
import { currentGuildId } from '../game/multiplayer/guilds'
import type { ChatMessage } from '../game/multiplayer/types'

interface ChatDrawerProps {
  locationId: string
}

/** Non-blocking chat drawer — never interrupts Primary Activity. */
export function ChatDrawer({ locationId }: ChatDrawerProps) {
  const [open, setOpen] = useState(false)
  const [channel, setChannel] = useState<'global' | 'local' | 'guild'>('global')
  const [body, setBody] = useState('')
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [notice, setNotice] = useState<string | null>(null)
  const guildId = currentGuildId()

  useEffect(() => {
    if (!isSignedIn() || !open) return
    const selected =
      channel === 'global'
        ? ({ kind: 'global' } as const)
        : channel === 'local'
          ? ({ kind: 'local', locationId } as const)
          : guildId
            ? ({ kind: 'guild', guildId } as const)
            : ({ kind: 'global' } as const)
    void listChatMessages(selected).then(setMessages)
  }, [open, channel, locationId, guildId])

  if (!isSignedIn()) return null

  return (
    <div className={open ? 'chat-drawer open' : 'chat-drawer'}>
      <button
        type="button"
        className="chat-drawer-toggle"
        aria-expanded={open}
        onClick={() => setOpen((value) => !value)}
      >
        Chat
      </button>
      {open && (
        <div className="chat-drawer-panel" role="dialog" aria-label="Chat">
          <div className="menu-tabs">
            <button
              type="button"
              className={channel === 'global' ? 'menu-tab active' : 'menu-tab'}
              onClick={() => setChannel('global')}
            >
              Global
            </button>
            <button
              type="button"
              className={channel === 'local' ? 'menu-tab active' : 'menu-tab'}
              onClick={() => setChannel('local')}
            >
              Local
            </button>
            <button
              type="button"
              className={channel === 'guild' ? 'menu-tab active' : 'menu-tab'}
              onClick={() => setChannel('guild')}
              disabled={!guildId}
            >
              Guild
            </button>
          </div>
          <ul className="chat-drawer-messages">
            {messages.map((message) => (
              <li key={message.id}>
                <strong>{message.username}</strong> {message.body}
              </li>
            ))}
          </ul>
          <form
            onSubmit={(event) => {
              event.preventDefault()
              const selected =
                channel === 'global'
                  ? ({ kind: 'global' } as const)
                  : channel === 'local'
                    ? ({ kind: 'local', locationId } as const)
                    : guildId
                      ? ({ kind: 'guild', guildId } as const)
                      : ({ kind: 'global' } as const)
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
              value={body}
              onChange={(event) => setBody(event.target.value)}
              placeholder="Message…"
              maxLength={240}
              aria-label="Chat message"
            />
            <button type="submit">Send</button>
          </form>
          {notice && <p className="muted tiny">{notice}</p>}
        </div>
      )}
    </div>
  )
}
