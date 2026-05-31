/**
 * Pure-DOM emoji confetti engine for LWC and mobile WebViews.
 *
 * Renders emoji as native text <span> elements animated with the Web
 * Animations API, with CSS transition fallback for iOS WKWebView.
 *
 * Physics tuned against canvas-confetti, ConfettiKit, and varun.ca/confetti.
 * Gravity accumulates in velocity (vy = vy * decay + gravity) for proper
 * parabolic arcs rather than constant positional offset.
 *
 * Exports:
 *   fireEmojiConfetti({ emojis, style, intensity })
 */

const FALLBACK_EMOJIS = ['🎉', '🥳', '✨', '💛'];

const INTENSITY_CONFIG = {
    normal:    { count: 30 },
    bigMoment: { count: 48 }
};

// ─── Container lifecycle ────────────────────────────────────────

function createOverlayContainer() {
    const el = document.createElement('div');
    Object.assign(el.style, {
        position: 'fixed',
        top: '0',
        left: '0',
        width: '100%',
        height: '100%',
        pointerEvents: 'none',
        zIndex: '10001',
        overflow: 'hidden'
    });
    document.body.appendChild(el);
    return el;
}

function scheduleCleanup(container, animations, maxDurationMs) {
    const safetyTimeout = maxDurationMs + 500;

    const finishedPromises = animations
        .filter(a => a && typeof a.finished === 'object')
        .map(a => a.finished.catch(() => {}));

    let cleaned = false;
    const cleanup = () => {
        if (cleaned) return;
        cleaned = true;
        container.remove();
    };

    if (finishedPromises.length > 0) {
        Promise.allSettled(finishedPromises).then(cleanup);
    }

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(cleanup, safetyTimeout);
}

// ─── Helpers ────────────────────────────────────────────────────

function randomBetween(min, max) {
    return Math.random() * (max - min) + min;
}

function shouldPreferCssTransitions() {
    if (typeof navigator === 'undefined') return false;
    const ua = navigator.userAgent || '';
    const isIOSDevice = /iPad|iPhone|iPod/.test(ua)
        || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
    return isIOSDevice;
}

function sanitizeEmojiToken(raw) {
    if (typeof raw !== 'string') return null;
    const token = raw.trim().replace(/\uFE0E/g, '');
    if (!token) return null;
    if (token.includes('\uFFFD') || token.includes('?')) return null;
    if (/^[A-Za-z0-9 !"#$%&'()*+,\-./:;<=>?@[\\\]^_`{|}~]+$/.test(token)) return null;
    return token;
}

function getSafeEmojiList(emojis) {
    if (!Array.isArray(emojis) || emojis.length === 0) return FALLBACK_EMOJIS;
    const safe = emojis.map(sanitizeEmojiToken).filter(Boolean);
    return safe.length > 0 ? safe : FALLBACK_EMOJIS;
}

function animateWithTransitionFallback(span, t) {
    span.style.transform = t.start.transform;
    span.style.opacity = `${t.start.opacity}`;

    const needsOpacity = t.start.opacity !== t.end.opacity;
    const transition = needsOpacity
        ? `transform ${t.duration}ms ${t.easing}, opacity ${t.duration}ms linear`
        : `transform ${t.duration}ms ${t.easing}`;

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
        span.style.transition = transition;
        span.style.webkitTransition = span.style.transition;
        span.style.transform = t.end.transform;
        if (needsOpacity) span.style.opacity = `${t.end.opacity}`;
    }, t.delay);
}

// ─── Physics simulation ─────────────────────────────────────────
//
// Gravity accumulates in velocity each frame (not added to position
// directly). This produces proper parabolic arcs matching
// canvas-confetti / varun.ca physics:
//   vx *= decay
//   vy = vy * decay + gravity
//   x += vx + drift
//   y += vy

function simulateTrajectory({ angle, velocity, decay, gravity, drift, frames }) {
    const points = [];
    let x = 0;
    let y = 0;
    let vx = Math.cos(angle) * velocity;
    let vy = Math.sin(angle) * velocity;

    for (let i = 0; i < frames; i += 1) {
        x += vx;
        y += vy;
        vx *= decay;
        vy = vy * decay + gravity;
        x += drift;
        points.push({ x, y });
    }

    return points;
}

function samplePosition(positions, progress) {
    const index = Math.max(
        0,
        Math.min(positions.length - 1, Math.floor(progress * (positions.length - 1)))
    );
    return positions[index];
}

// ─── Cannon (CSS-transition friendly) ────────────────────────────
//
// For iOS WKWebView where only start→end is animated. Emojis burst
// from bottom-centre outward in a 180° upper arc, travelling far
// enough off-screen to feel like a cannon shot exiting the viewport.

function buildCannonCssTrajectory() {
    const w = window.innerWidth;
    const h = window.innerHeight;

    const angle = randomBetween(-1.4, 1.4);
    const reach = Math.max(w, h) * randomBetween(0.95, 1.4);
    const endX = Math.sin(angle) * reach;
    const endY = -Math.cos(angle) * reach;

    return {
        left: `${w * randomBetween(0.44, 0.56)}px`,
        top: `${h * 0.92}px`,
        start: {
            transform: 'translate(0px, 0px) scale(0.45)',
            opacity: 1
        },
        end: {
            transform: `translate(${endX.toFixed(1)}px, ${endY.toFixed(1)}px) scale(${randomBetween(0.82, 1.0).toFixed(3)})`,
            opacity: randomBetween(0.0, 0.15)
        },
        duration: randomBetween(2600, 3600),
        delay: randomBetween(0, 80),
        easing: 'cubic-bezier(0.16, 0.7, 0.3, 1)'
    };
}

// ─── Cannon (WAAPI keyframed) ────────────────────────────────────

function buildCannonTrajectory() {
    const w = window.innerWidth;
    const h = window.innerHeight;

    const spread = randomBetween(-1.05, 1.05);
    const launchAngle = -Math.PI / 2 + spread;
    const startVelocity = randomBetween(28, 38);
    const drift = randomBetween(-0.3, 0.3);
    const endOpacity = randomBetween(0.08, 0.2);

    const positions = simulateTrajectory({
        angle: launchAngle,
        velocity: startVelocity,
        decay: 0.97,
        gravity: 0.35,
        drift,
        frames: 180
    });

    const STEPS = 48;
    const keyframes = [];

    for (let i = 0; i <= STEPS; i++) {
        const t = i / STEPS;
        const p = samplePosition(positions, t);

        const scale = t < 0.18
            ? 0.55 + 0.4 * (t / 0.18)
            : 0.95 - 0.19 * ((t - 0.18) / 0.82);

        const opacity = t < 0.3
            ? 1
            : 1 - (1 - endOpacity) * ((t - 0.3) / 0.7);

        keyframes.push({
            transform: `translate(${p.x}px, ${p.y}px) scale(${scale.toFixed(3)})`,
            opacity: parseFloat(opacity.toFixed(3)),
            offset: parseFloat(t.toFixed(4))
        });
    }

    const last = keyframes[keyframes.length - 1];

    return {
        left: `${w * randomBetween(0.46, 0.54)}px`,
        top: `${h * 0.9}px`,
        start: {
            transform: keyframes[0].transform,
            opacity: keyframes[0].opacity
        },
        end: {
            transform: last.transform,
            opacity: last.opacity
        },
        keyframes,
        duration: randomBetween(3200, 3800),
        delay: randomBetween(0, 60),
        easing: 'linear'
    };
}

// ─── Fall ────────────────────────────────────────────────────────

function buildFallTrajectory() {
    const w = window.innerWidth;
    const h = window.innerHeight;
    const startX = randomBetween(5, 95);
    const drift = randomBetween(-0.8, 0.8);
    const midX = drift * w * 0.08;
    const endX = drift * w * 0.16;
    const endY = h * randomBetween(1.05, 1.35);

    return {
        left: `${(w * startX) / 100}px`,
        top: `${-h * 0.05}px`,
        start: { transform: 'translate(0px, 0px) scale(0.8)', opacity: 1 },
        end:   { transform: `translate(${endX}px, ${endY}px) scale(0.72)`, opacity: 1 },
        keyframes: [
            { transform: 'translate(0px, 0px) scale(0.8)', opacity: 1, offset: 0 },
            { transform: `translate(${midX}px, ${endY * 0.4}px) scale(0.78)`, opacity: 1, offset: 0.45 },
            { transform: `translate(${endX}px, ${endY}px) scale(0.72)`, opacity: 1, offset: 1 }
        ],
        duration: randomBetween(3200, 4300),
        delay: randomBetween(0, 600),
        easing: 'linear'
    };
}

// ─── Rise ────────────────────────────────────────────────────────

function buildRiseTrajectory() {
    const w = window.innerWidth;
    const h = window.innerHeight;
    const startX = randomBetween(10, 90);
    const drift = randomBetween(-0.9, 0.9);
    const endY = -h * randomBetween(1.05, 1.3);

    return {
        left: `${(w * startX) / 100}px`,
        top: `${h * 1.05}px`,
        start: { transform: 'translate(0px, 0px) scale(0.9)', opacity: 1 },
        end:   { transform: `translate(${drift * w * 0.12}px, ${endY}px) scale(1.02)`, opacity: 1 },
        duration: randomBetween(3600, 4800),
        delay: randomBetween(0, 400),
        easing: 'linear'
    };
}

// ─── Drift ──────────────────────────────────────────────────────

function buildDriftTrajectory() {
    const w = window.innerWidth;
    const h = window.innerHeight;
    const startY = randomBetween(15, 85);
    const bob = randomBetween(-0.18, 0.18) * h;
    const endX = w * randomBetween(1.0, 1.25);

    return {
        left: `${-w * 0.04}px`,
        top: `${(h * startY) / 100}px`,
        start: { transform: 'translate(0px, 0px) scale(0.8)', opacity: 1 },
        end:   { transform: `translate(${endX}px, ${bob}px) scale(0.82)`, opacity: 1 },
        duration: randomBetween(3000, 4000),
        delay: randomBetween(0, 700),
        easing: 'linear'
    };
}

// ─── Approach ───────────────────────────────────────────────────

function buildApproachTrajectory() {
    const w = window.innerWidth;
    const h = window.innerHeight;
    const angle = Math.random() * Math.PI * 2;

    const positions = simulateTrajectory({
        angle,
        velocity: randomBetween(35, 48),
        decay: 0.97,
        gravity: 0.25,
        drift: 0,
        frames: 140
    });

    const STEPS = 36;
    const keyframes = [];

    for (let i = 0; i <= STEPS; i++) {
        const t = i / STEPS;
        const p = samplePosition(positions, t);
        const scale = 0.4 + 0.6 * Math.min(t / 0.25, 1);

        keyframes.push({
            transform: `translate(${p.x}px, ${p.y}px) scale(${scale.toFixed(3)})`,
            opacity: 1,
            offset: parseFloat(t.toFixed(4))
        });
    }

    const last = keyframes[keyframes.length - 1];

    return {
        left: `${w * 0.5}px`,
        top: `${h * 0.5}px`,
        start: { transform: keyframes[0].transform, opacity: 1 },
        end:   { transform: last.transform, opacity: 1 },
        keyframes,
        duration: randomBetween(2200, 2800),
        delay: randomBetween(0, 180),
        easing: 'linear'
    };
}

const STYLE_BUILDERS = {
    Cannon: buildCannonTrajectory,
    Fall: buildFallTrajectory,
    Rise: buildRiseTrajectory,
    Drift: buildDriftTrajectory,
    Approach: buildApproachTrajectory
};

// ─── Public API ─────────────────────────────────────────────────

/**
 * Fire a DOM-based emoji confetti animation. Full-screen viewport overlay.
 *
 * @param {Object} options
 * @param {string[]} [options.emojis]    Emoji characters. Each particle randomly picks one.
 * @param {string}   [options.style]     'Cannon' | 'Fall' | 'Rise' | 'Drift' | 'Approach'
 * @param {string}   [options.intensity] 'normal' | 'bigMoment'
 */
export function fireEmojiConfetti({ emojis, style, intensity } = {}) {
    if (typeof window === 'undefined') return;
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

    const supportsWaapi = typeof Element !== 'undefined' && Element.prototype.animate;
    const useWaapi = supportsWaapi && !shouldPreferCssTransitions();

    const emojiList = getSafeEmojiList(emojis);
    const config = INTENSITY_CONFIG[intensity] || INTENSITY_CONFIG.normal;

    const resolvedStyle = STYLE_BUILDERS[style] ? style : 'Cannon';
    const builder = (!useWaapi && resolvedStyle === 'Cannon')
        ? buildCannonCssTrajectory
        : STYLE_BUILDERS[resolvedStyle];

    const container = createOverlayContainer();
    const animations = [];
    let maxDuration = 0;

    for (let i = 0; i < config.count; i += 1) {
        const emoji = emojiList[Math.floor(Math.random() * emojiList.length)];
        const t = builder();

        const span = document.createElement('span');
        span.textContent = emoji;
        span.setAttribute('aria-hidden', 'true');
        Object.assign(span.style, {
            position: 'absolute',
            left: t.left,
            top: t.top,
            fontSize: `${randomBetween(18, 28)}px`,
            lineHeight: '1',
            display: 'inline-block',
            willChange: 'transform, opacity',
            pointerEvents: 'none',
            userSelect: 'none',
            webkitUserSelect: 'none',
            backfaceVisibility: 'hidden',
            transform: t.start.transform,
            opacity: `${t.start.opacity}`
        });

        container.appendChild(span);

        const totalDuration = t.duration + t.delay;
        if (totalDuration > maxDuration) maxDuration = totalDuration;

        if (useWaapi) {
            try {
                const frames = t.keyframes || [t.start, t.end];
                const anim = span.animate(frames, {
                    duration: t.duration,
                    delay: t.delay,
                    easing: t.easing,
                    fill: 'forwards'
                });
                animations.push(anim);
            // eslint-disable-next-line no-unused-vars
            } catch (e) {
                animateWithTransitionFallback(span, t);
            }
        } else {
            animateWithTransitionFallback(span, t);
        }
    }

    scheduleCleanup(container, animations, maxDuration);
}