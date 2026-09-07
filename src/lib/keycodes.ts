// Browser KeyboardEvent.code -> macOS virtual key code (stable ANSI layout constants).
// Used by ShortcutRecorder to translate what the user types into the CGEvent-ready
// InjectAction the Electron main process (electron/hid-capture.ts) understands.

export const CODE_TO_VK: Record<string, number> = {
  KeyA: 0x00, KeyS: 0x01, KeyD: 0x02, KeyF: 0x03, KeyH: 0x04, KeyG: 0x05,
  KeyZ: 0x06, KeyX: 0x07, KeyC: 0x08, KeyV: 0x09, KeyB: 0x0b, KeyQ: 0x0c,
  KeyW: 0x0d, KeyE: 0x0e, KeyR: 0x0f, KeyY: 0x10, KeyT: 0x11, KeyO: 0x1f,
  KeyU: 0x20, KeyI: 0x22, KeyP: 0x23, KeyL: 0x25, KeyJ: 0x26, KeyK: 0x28,
  KeyN: 0x2d, KeyM: 0x2e,
  Digit1: 0x12, Digit2: 0x13, Digit3: 0x14, Digit4: 0x15, Digit5: 0x17,
  Digit6: 0x16, Digit7: 0x1a, Digit8: 0x1c, Digit9: 0x19, Digit0: 0x1d,
  Space: 0x31, Tab: 0x30, Backspace: 0x33, Enter: 0x24, Escape: 0x35,
  ArrowLeft: 0x7b, ArrowRight: 0x7c, ArrowDown: 0x7d, ArrowUp: 0x7e,
}

const VK_TO_LABEL: Record<number, string> = Object.fromEntries(
  Object.entries(CODE_TO_VK).map(([code, vk]) => [
    vk,
    code
      .replace('Key', '')
      .replace('Digit', '')
      .replace('Arrow', '')
      .replace('Backspace', '⌫')
      .replace('Enter', '⏎')
      .replace('Escape', 'Esc')
      .replace('Space', '␣'),
  ]),
)
const ARROW_GLYPH: Record<number, string> = { 0x7b: '←', 0x7c: '→', 0x7d: '↓', 0x7e: '↑' }

export function vkLabel(keyCode: number): string {
  return ARROW_GLYPH[keyCode] ?? VK_TO_LABEL[keyCode] ?? `#${keyCode}`
}

export function flagsLabel(flags?: string[]): string {
  if (!flags?.length) return ''
  const glyphs: Record<string, string> = { cmd: '⌘', shift: '⇧', ctrl: '⌃', option: '⌥' }
  return flags.map((f) => glyphs[f] ?? f).join('')
}
