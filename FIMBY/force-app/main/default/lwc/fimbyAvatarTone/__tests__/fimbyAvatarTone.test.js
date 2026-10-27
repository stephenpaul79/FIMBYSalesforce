import {
  getInitials,
  getAvatarToneIndex,
  getAvatarTone,
  getAvatarToneStyle,
  TONE_HEX
} from "c/fimbyAvatarTone";

// Keep in sync with FimbyAvatarToneTest.cls — both runtimes must agree.
const ID_FIXTURES = [
  { input: { contactId: "003OL00000tXhWNYA0" }, index: 3 },
  { input: { contactId: "003OL00000tXhWN" }, index: 3 },
  { input: { contactId: "003OL00000bwBSSYA2" }, index: 6 },
  { input: { contactId: "003OL000011KH5uYAG" }, index: 4 },
  { input: { contactId: "003OL00000rBHooYAG" }, index: 2 },
  {
    input: {
      contactId: "003OL00000xUb3OYAS",
      organizationAccountId: "001OL00000qGuI3YAK",
      isOrganization: true
    },
    index: 1
  },
  {
    input: { organizationAccountId: "001OL00000qGuI3YAK", isOrganization: true },
    index: 0
  },
  { input: { name: "Sarah Chen" }, index: 6 }
];

describe("c/fimbyAvatarTone", () => {
  describe("getInitials", () => {
    it("builds up to two initials", () => {
      expect(getInitials("Sarah Chen")).toBe("SC");
      expect(getInitials("rosa")).toBe("R");
      expect(getInitials("Mary Anne Lee")).toBe("MA");
      expect(getInitials("  ")).toBe("?");
      expect(getInitials(null)).toBe("?");
    });

    it("handles accents, apostrophes, CJK and astral characters", () => {
      expect(getInitials("élodie ñúñez")).toBe("ÉÑ");
      expect(getInitials("O'Brien Kelly")).toBe("OK");
      expect(getInitials("陈 美")).toBe("陈美");
      expect(getInitials("𝒜lex 𝒵ed")).toBe("𝒜𝒵");
    });
  });

  describe("getAvatarToneIndex", () => {
    it.each(ID_FIXTURES)("matches the Apex fixture for %o", ({ input, index }) => {
      expect(getAvatarToneIndex(input)).toBe(index);
    });

    it("treats 15- and 18-character Ids as the same identity", () => {
      expect(getAvatarToneIndex({ contactId: "003OL00000tXhWNYA0" })).toBe(
        getAvatarToneIndex({ contactId: "003OL00000tXhWN" })
      );
    });

    it("prefers the Contact Id over the name", () => {
      expect(
        getAvatarToneIndex({ contactId: "003OL00000tXhWNYA0", name: "Sarah Chen" })
      ).toBe(3);
    });

    it("never hashes the literal label 'You' when an Id is present", () => {
      expect(
        getAvatarToneIndex({ contactId: "003OL00000bwBSSYA2", name: "You" })
      ).toBe(6);
    });

    it("ignores invalid Ids and falls back to the name", () => {
      expect(getAvatarToneIndex({ contactId: "not-an-id", name: "Sarah Chen" })).toBe(6);
    });

    it("normalizes name whitespace and case", () => {
      expect(getAvatarToneIndex({ name: "  sarah   CHEN " })).toBe(6);
    });

    it("still accepts a plain name string", () => {
      expect(getAvatarToneIndex("Sarah Chen")).toBe(6);
    });
  });

  describe("getAvatarTone / getAvatarToneStyle", () => {
    it("returns an earth-tone token with a light-theme fallback", () => {
      expect(getAvatarTone({ contactId: "003OL00000tXhWNYA0" })).toBe(
        "var(--fimby-earth-terracotta, #8A5936)"
      );
      expect(getAvatarTone({ name: "" })).toMatch(/^var\(--fimby-earth-/);
    });

    it("never uses the CTA teal", () => {
      for (let i = 0; i < 50; i++) {
        expect(getAvatarTone({ name: `Neighbour ${i}` })).not.toContain("teal");
      }
    });

    it("builds an inline background style", () => {
      expect(getAvatarToneStyle({ contactId: "003OL000011KH5uYAG" })).toBe(
        "background-color: var(--fimby-earth-dusty-violet, #625A76);"
      );
      expect(getAvatarToneStyle(undefined)).toMatch(/^background-color: var\(--fimby-earth-/);
    });

    it("exposes the light-theme hex palette in index order", () => {
      expect(TONE_HEX).toEqual([
        "#476B4C",
        "#7D6234",
        "#4E6878",
        "#8A5936",
        "#625A76",
        "#566744",
        "#6B5E50"
      ]);
    });
  });
});
