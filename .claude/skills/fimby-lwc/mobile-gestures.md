# LWC Mobile Gesture & Interactive Menu Patterns

Pitfalls learned from swipe-to-reveal and kebab-menu work. Load when touching gesture or dropdown code in `*.js`/`*.html`/`*.css`.

## `preventDefault()` in touch handlers kills all click events
`event.preventDefault()` in `touchend` stops the browser synthesizing `click` — not just for the wrapper but for **every child** underneath. Breaks plain row taps (navigation) and taps on revealed action buttons. Fix with two guards:
```javascript
handleSwipeStart(event) {
    if (event.target.closest('.swipe-action')) return; // guard #1: let action-button clicks through
    // ... swipe tracking
}
handleSwipeEnd(event) {
    if (!this._swipeThreadId) return;
    if (this._swiping) { event.preventDefault(); } // guard #2: only prevent default for actual swipes
    // ... snap logic
}
```
Guard #1 exempts action buttons from swipe tracking; guard #2 lets plain taps (where `_swiping` stays `false`) still fire `click` for row navigation.

## Swipe gestures must only reveal — never act
Swipe handlers only translate the foreground to reveal/hide buttons. Apex/database calls belong on the revealed button's `onclick`, not the swipe handler. Prevents accidental triggers; gives a clear tap target.

## `overflow: hidden` clips absolutely-positioned menus
Dropdowns inside a scroll container (`overflow: hidden`) are invisible even with `z-index`. Either: (1) **preferred** — render one shared menu element **outside** the scroll container (sibling), positioned with `position: fixed` using `getBoundingClientRect()`; or close on backdrop click **and** Escape for accessibility.
```javascript
const rect = triggerBtn.getBoundingClientRect();
this._menuTop = rect.bottom + 4;
this._menuRight = window.innerWidth - rect.right;
```

## Imperative DOM changes are lost on re-render
Direct `element.style.transform = ...` is wiped when any `@track` property changes and LWC re-renders. When mixing imperative styles (swipe transforms) with reactive updates (marking a thread read), close/reset the swipe state **before** updating tracked properties.

## Impact Icons need no CSS filters
`Impact_Icons` are pre-colored for their backgrounds. Avoid `filter: brightness(0) invert(1)` — it washes out the artwork and creates a white-overlay effect.

## One open row at a time
Track the open swipe (`_openSwipeThreadId`) / open menu (`_menuThreadId`) and close it when another row starts interacting — prevents multiple rows being open at once.
