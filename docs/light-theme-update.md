Your current UI is actually a **warm sepia/cream theme** (think Solarized Light or
paper/e-reader mode), whereas light-mode power users usually expect a crisp, modern
neutral white UI.

When designers or users ask for a "proper white theme," they are generally looking for
these specific standard light-mode patterns:

* **Pure White & Cool Grays:** Replacing the warm parchment background with pure white
  (`#FFFFFF`) for cards/panels set against a very subtle cool-gray canvas (like
`#F8FAFC` or `#F9FAFB`).
* **Defined Panel Hierarchy:** Creating clear visual depth using pure white containers
  on a light grey background separated by crisp, subtle borders (e.g., `#E2E8F0`) rather
than tone-on-tone cream.
* **Sharper Text Contrast:** Switching muted dark gray text to high-contrast charcoal
  (`#0F172A` or `#18181B`). Right now, elements like the chart glyph labels and "Solar
Prism" subtext fall into a low-contrast middle ground that's hard to read in bright
environments.
* **Vibrant Focus & Accent Colors:** Pure white themes rely on intentional accent colors
  (for primary action buttons, active states, or chart highlights) to guide the eye;
monochrome light UIs often feel flat or washed out without them.

If you like how this looks, keep it as a **"Warm"** or **"Paper"** preset, and add a
standard **"Light"** theme that uses clean `#FFFFFF` and neutral grays (the standard
Apple, Tailwind, or Vercel aesthetic).
