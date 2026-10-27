import {
  getInitials,
  getAvatarTone,
  getAvatarToneStyle
} from "c/fimbyAvatarTone";

const NAMES = [
  "Sarah Chen",
  "Rosa Alvarez",
  "Marcus Bell",
  "Amir Haddad",
  "Joan Whitecloud",
  "Appy Review",
  "Maya Chen",
  "Lee Park",
  "Priya Singh",
  "Tom Nguyen"
];

describe("c/fimbyAvatarTone", () => {
  it("builds up to two initials", () => {
    expect(getInitials("Sarah Chen")).toBe("SC");
    expect(getInitials("rosa")).toBe("R");
    expect(getInitials("Mary Anne Lee")).toBe("MA");
    expect(getInitials("  ")).toBe("?");
    expect(getInitials(null)).toBe("?");
  });

  it("gives the same person the same tone every time", () => {
    expect(getAvatarTone("Sarah Chen")).toBe(getAvatarTone("Sarah Chen"));
    expect(getAvatarTone(" sarah chen ")).toBe(getAvatarTone("Sarah Chen"));
  });

  it("only uses earth tones, never the CTA colour", () => {
    NAMES.forEach((name) => {
      const tone = getAvatarTone(name);
      expect(tone).toMatch(/^var\(--fimby-earth-[a-z-]+, #[0-9A-F]{6}\)$/);
      expect(tone).not.toContain("earth-teal");
    });
  });

  it("spreads a neighbourhood across several tones", () => {
    const tones = new Set(NAMES.map(getAvatarTone));
    expect(tones.size).toBeGreaterThanOrEqual(4);
  });

  it("handles a missing name", () => {
    expect(getAvatarTone("")).toMatch(/^var\(--fimby-earth-/);
    expect(getAvatarToneStyle(undefined)).toMatch(
      /^background-color: var\(--fimby-earth-/
    );
  });
});
