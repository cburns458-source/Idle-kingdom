import {
  handleStagingGate,
  TESTER_COOKIE,
  TESTER_UNLOCK_PATH,
  testerToken,
  type StagingGateEnv,
} from './staging_gate'

const SITE = 'https://test.restoriaidle.com'
const KEY = 'quiet harbor lantern'

function gateEnv(passkey: string | null = KEY): StagingGateEnv & { served: string[] } {
  const served: string[] = []
  return {
    served,
    TESTER_PASSKEY: passkey ?? undefined,
    ASSETS: {
      fetch: async (request: Request) => {
        served.push(new URL(request.url).pathname)
        return new Response('game', { status: 200 })
      },
    },
  }
}

function unlockRequest(passkey: string): Request {
  return new Request(`${SITE}${TESTER_UNLOCK_PATH}`, {
    method: 'POST',
    body: new URLSearchParams({ passkey }),
  })
}

describe('staging gate', () => {
  it('stays locked when the secret is missing', async () => {
    const env = gateEnv(null)
    const response = await handleStagingGate(new Request(`${SITE}/`), env)
    expect(response.status).toBe(503)
    expect(env.served).toEqual([])
  })

  it('shows the key form without serving the game', async () => {
    const env = gateEnv()
    const response = await handleStagingGate(new Request(`${SITE}/main.dart.js`), env)
    const html = await response.text()
    expect(response.status).toBe(401)
    expect(response.headers.get('Cache-Control')).toBe('no-store')
    expect(html).toContain(TESTER_UNLOCK_PATH)
    expect(html).not.toContain(KEY)
    expect(env.served).toEqual([])
  })

  it('refuses a wrong key', async () => {
    const env = gateEnv()
    const response = await handleStagingGate(unlockRequest('nope'), env)
    expect(response.status).toBe(401)
    expect(response.headers.get('Set-Cookie')).toBeNull()
  })

  it('sets a cookie for the right key and then serves the game', async () => {
    const env = gateEnv()
    const response = await handleStagingGate(unlockRequest(`  ${KEY} `), env)
    expect(response.status).toBe(303)
    expect(response.headers.get('Location')).toBe('/')
    const cookie = response.headers.get('Set-Cookie') ?? ''
    expect(cookie).toContain('HttpOnly')
    expect(cookie).toContain('Secure')
    expect(cookie).not.toContain(KEY)

    const token = cookie.split(';')[0].split('=')[1]
    const next = await handleStagingGate(
      new Request(`${SITE}/main.dart.js`, { headers: { Cookie: `other=1; ${TESTER_COOKIE}=${token}` } }),
      env,
    )
    expect(next.status).toBe(200)
    expect(env.served).toEqual(['/main.dart.js'])
  })

  it('signs everyone out when the key is rotated', async () => {
    const oldToken = await testerToken(KEY)
    const env = gateEnv('new key entirely')
    const response = await handleStagingGate(
      new Request(`${SITE}/`, { headers: { Cookie: `${TESTER_COOKIE}=${oldToken}` } }),
      env,
    )
    expect(response.status).toBe(401)
    expect(env.served).toEqual([])
  })

  it('sends a plain visit to the unlock path back home', async () => {
    const response = await handleStagingGate(new Request(`${SITE}${TESTER_UNLOCK_PATH}`), gateEnv())
    expect(response.status).toBe(303)
    expect(response.headers.get('Location')).toBe(`${SITE}/`)
  })
})
