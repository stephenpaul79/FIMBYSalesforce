// Earth tones with white initials at >= 4.5:1 in light and dark themes.
// earth-teal is excluded: it reads as the CTA colour and its dark variant misses AA.
const TONES = [
    'var(--fimby-earth-sage, #476B4C)',
    'var(--fimby-earth-ochre, #7D6234)',
    'var(--fimby-earth-slate, #4E6878)',
    'var(--fimby-earth-terracotta, #8A5936)',
    'var(--fimby-earth-dusty-violet, #625A76)',
    'var(--fimby-earth-moss, #566744)',
    'var(--fimby-earth-driftwood, #6B5E50)'
];

export function getInitials(name) {
    const words = (name || '').trim().split(/\s+/).filter(Boolean);
    if (words.length === 0) return '?';
    return words
        .slice(0, 2)
        .map((word) => word.charAt(0))
        .join('')
        .toUpperCase();
}

export function getAvatarTone(name) {
    const key = (name || '').trim().toLowerCase();
    let hash = 0;
    for (let i = 0; i < key.length; i++) {
        hash = (hash * 31 + key.charCodeAt(i)) % 2147483647;
    }
    return TONES[hash % TONES.length];
}

export function getAvatarToneStyle(name) {
    return `background-color: ${getAvatarTone(name)};`;
}
