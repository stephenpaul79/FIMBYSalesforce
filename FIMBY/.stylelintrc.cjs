module.exports = {
  extends: ["stylelint-config-standard"],
  plugins: ["stylelint-no-unsupported-browser-features"],
  rules: {
    // ─── Browser compatibility (the whole point of this setup) ───
    "plugin/no-unsupported-browser-features": [
      true,
      {
        severity: "warning",
        ignore: [
          "css-nesting",
          "css3-cursors", // cursor:pointer is a no-op on touch — harmless graceful degradation
        ],
      },
    ],

    // ─── Disable rules that push toward LESS compatible CSS ───
    // Traditional @media (min-width: 768px) has universal support;
    // the "context" range syntax (width >= 768px) only landed in Safari 16.4.
    "media-feature-range-notation": null,
    // rgba(0,0,0,0.5) works everywhere; modern rgb(0 0 0 / 50%) is newer.
    "color-function-notation": null,
    "color-function-alias-notation": null,
    // Decimal (0.5) vs percentage (50%) for alpha — both fine.
    "alpha-value-notation": null,

    // ─── Formatting rules — Prettier owns these ───
    "declaration-block-single-line-max-declarations": null,
    "comment-empty-line-before": null,
    "at-rule-empty-line-before": null,
    "declaration-empty-line-before": null,
    "rule-empty-line-before": null,

    // ─── LWC naming conventions (camelCase is standard) ───
    "selector-class-pattern": null,
    "keyframes-name-pattern": null,
    "custom-property-pattern": null,

    // ─── LWC shadow-DOM and custom elements ───
    "selector-pseudo-class-no-unknown": [
      true,
      { ignorePseudoClasses: ["host", "host-context"] },
    ],
    "selector-type-no-unknown": [
      true,
      {
        ignoreTypes: [
          /^lightning-/,
          /^c-fimby-/,
        ],
      },
    ],

    // ─── Allow -webkit- prefixes kept intentionally for Safari ───
    "property-no-vendor-prefix": null,
    "value-no-vendor-prefix": null,

    // ─── Downgrade noisy-but-harmless rules to warnings ───
    "color-hex-length": null,
    "shorthand-property-no-redundant-values": [true, { severity: "warning" }],
    "declaration-block-no-redundant-longhand-properties": [true, { severity: "warning" }],
    // Common intentional pattern: .btn:hover:not(:disabled) then .btn:focus-visible
    "no-descending-specificity": [true, { severity: "warning" }],

    // LWC CSS files don't use @import
    "no-empty-source": null,

    // currentColor casing — not a compat issue
    "value-keyword-case": null,
    // 0px vs 0 — not a compat issue
    "length-zero-no-unit": null,
  },
};
