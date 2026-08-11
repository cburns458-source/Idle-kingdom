import { describe, expect, it } from 'vitest'
import { hasRenderableContent } from './LocationView'

describe('hasRenderableContent', () => {
  it('treats null/undefined/false as empty', () => {
    expect(hasRenderableContent(null)).toBe(false)
    expect(hasRenderableContent(undefined)).toBe(false)
    expect(hasRenderableContent(false)).toBe(false)
  })

  // App.tsx always passes statusPanel as a `<>...</>` fragment, even when
  // every conditional child inside evaluates to false. This is the exact
  // shape that caused the location activities band to be permanently hidden
  // once (fixed, then regressed, then fixed again) — guard against it.
  it('treats an empty fragment (all children false) as empty, not renderable', () => {
    const activeShopId: string | null = null
    const activeNpcId: string | null = null
    const empty = (
      <>
        {activeShopId && <div>shop</div>}
        {activeNpcId && <div>npc</div>}
      </>
    )
    expect(hasRenderableContent(empty)).toBe(false)
  })

  it('treats a fragment with at least one real child as renderable', () => {
    const activeShopId: string | null = 'SHP-0001'
    const withContent = (
      <>
        {activeShopId && <div>shop</div>}
        {false && <div>npc</div>}
      </>
    )
    expect(hasRenderableContent(withContent)).toBe(true)
  })

  it('treats nested fragments as renderable only if they contain real content', () => {
    const nestedEmpty = (
      <>
        <>{false && <div>a</div>}</>
        {null}
      </>
    )
    expect(hasRenderableContent(nestedEmpty)).toBe(false)

    const nestedWithContent = (
      <>
        <>{true && <div>a</div>}</>
      </>
    )
    expect(hasRenderableContent(nestedWithContent)).toBe(true)
  })

  it('treats a plain element as renderable', () => {
    expect(hasRenderableContent(<div>hello</div>)).toBe(true)
  })
})
