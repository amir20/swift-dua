/**
 * The app's folder-lens color formula, ported from Sources/Halo/Palette.swift:
 * hues step by the golden angle from 35° at fixed dark-mode lightness/chroma,
 * so any number of slices stay separated but read as one family.
 */
const GOLDEN_ANGLE = 137.507_764;
const START_HUE = 35;

export function folderHue(index: number): string {
  const h = (START_HUE + index * GOLDEN_ANGLE) % 360;
  return `oklch(0.72 0.125 ${h.toFixed(3)})`;
}
