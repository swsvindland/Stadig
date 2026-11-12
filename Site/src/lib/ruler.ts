// The ruler's tick marks on a 0–100 scale: a long tick every 10, a middle one every 5, short ones
// between. Drawn in a 100 × 10 viewBox stretched to the width, with non-scaling strokes.
export const tickPath = Array.from({ length: 101 }, (_, i) => {
  const x = i === 0 ? 0.05 : i === 100 ? 99.95 : i;
  const h = i % 10 === 0 ? 10 : i % 5 === 0 ? 6 : 3.5;
  return `M${x} 0V${h}`;
}).join("");

/** Strength's levels, which the apps mark on the ruler. */
export const levels = [
  { at: 20, long: "Beginner", short: "Beginner" },
  { at: 40, long: "Novice", short: "Novice" },
  { at: 60, long: "Intermediate", short: "Intermed." },
  { at: 80, long: "Advanced", short: "Advanced" },
  { at: 100, long: "Elite", short: "Elite" },
];

/** The paper-shade accents, for the dots on the light buttons. */
export const buttonDot = { lift: "#3355e0", macro: "#12804f" } as const;
