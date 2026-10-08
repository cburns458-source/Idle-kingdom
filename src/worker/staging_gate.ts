/**
 * Test-site gate for restoria-idlerpg-staging. Runs in front of the static
 * Flutter build and only lets a request through when it carries the cookie
 * minted from the TESTER_PASSKEY Worker secret. The key never reaches the
 * browser; the live Worker has no script and so no gate.
 */

export interface AssetFetcher {
  fetch(request: Request): Promise<Response>
}

export interface StagingGateEnv {
  ASSETS: AssetFetcher
  TESTER_PASSKEY?: string
}

export const TESTER_COOKIE = 'ik_tester'
export const TESTER_UNLOCK_PATH = '/__tester'
const TOKEN_LABEL = 'ik-tester-v1'
const COOKIE_MAX_AGE_SECONDS = 60 * 60 * 24 * 90

/** Changes whenever the secret does, so rotating it signs every tester out. */
export async function testerToken(passkey: string): Promise<string> {
  const encoder = new TextEncoder()
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(passkey),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const mac = await crypto.subtle.sign('HMAC', key, encoder.encode(TOKEN_LABEL))
  return [...new Uint8Array(mac)].map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

function sameToken(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return diff === 0
}

function cookieValue(request: Request, name: string): string | null {
  const header = request.headers.get('Cookie')
  if (!header) return null
  for (const part of header.split(';')) {
    const eq = part.indexOf('=')
    if (eq < 0) continue
    if (part.slice(0, eq).trim() === name) return part.slice(eq + 1).trim()
  }
  return null
}

const PAGE_HEADERS: Record<string, string> = {
  'Content-Type': 'text/html; charset=utf-8',
  'Cache-Control': 'no-store',
  'X-Robots-Tag': 'noindex, nofollow',
  'X-Frame-Options': 'DENY',
  'Content-Security-Policy':
    "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
}

function page(status: number, message: string, withForm: boolean): Response {
  const form = withForm
    ? `<form method="post" action="${TESTER_UNLOCK_PATH}">
        <input type="password" name="passkey" autocomplete="current-password" placeholder="Tester key" required autofocus>
        <button type="submit">Enter</button>
      </form>`
    : ''
  const body = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>RestoriaIdle test</title>
<style>
  body { margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
         background: #1F1610; color: #EADBC0; font-family: system-ui, sans-serif; }
  main { max-width: 22rem; padding: 1.5rem; text-align: center; }
  h1 { font-size: 1.25rem; margin: 0 0 0.75rem; }
  p { margin: 0 0 1rem; line-height: 1.4; }
  input, button { font: inherit; padding: 0.6rem 0.8rem; border-radius: 6px; border: 1px solid #6B5235; }
  input { width: 100%; box-sizing: border-box; margin-bottom: 0.75rem; background: #2A1F16; color: inherit; }
  button { background: #8A6A3A; color: #1F1610; cursor: pointer; width: 100%; }
</style>
</head>
<body><main><h1>RestoriaIdle test</h1><p>${message}</p>${form}</main></body>
</html>`
  return new Response(body, { status, headers: PAGE_HEADERS })
}

async function unlock(request: Request, expected: string): Promise<Response> {
  let submitted = ''
  try {
    const form = await request.formData()
    const value = form.get('passkey')
    if (typeof value === 'string') submitted = value.trim()
  } catch {
    submitted = ''
  }
  if (!submitted || !sameToken(await testerToken(submitted), expected)) {
    return page(401, 'That key is not right.', true)
  }
  return new Response(null, {
    status: 303,
    headers: {
      Location: '/',
      'Cache-Control': 'no-store',
      'Set-Cookie': `${TESTER_COOKIE}=${expected}; Path=/; Max-Age=${COOKIE_MAX_AGE_SECONDS}; HttpOnly; Secure; SameSite=Lax`,
    },
  })
}

export async function handleStagingGate(request: Request, env: StagingGateEnv): Promise<Response> {
  const passkey = env.TESTER_PASSKEY?.trim()
  if (!passkey) return page(503, 'The test site is locked until its tester key is set.', false)

  const expected = await testerToken(passkey)
  const url = new URL(request.url)

  if (url.pathname === TESTER_UNLOCK_PATH) {
    if (request.method === 'POST') return unlock(request, expected)
    return Response.redirect(new URL('/', url).toString(), 303)
  }

  const presented = cookieValue(request, TESTER_COOKIE)
  if (presented && sameToken(presented, expected)) return env.ASSETS.fetch(request)

  return page(401, 'Enter the tester key to continue.', true)
}
