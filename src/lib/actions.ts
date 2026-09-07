// Structural mirror of electron/hid-capture.ts's InjectAction union — the renderer can't import
// that file directly (it pulls in Node built-ins Vite won't bundle for the browser context), so
// the shape is duplicated here and kept in sync by hand.

export type ModifierFlag = 'cmd' | 'shift' | 'ctrl' | 'option'

export interface KeyAction {
  kind: 'key'
  keyCode: number
  flags?: ModifierFlag[]
  extraKeyDown?: number
  extraKeyUp?: number
  system?: boolean
  label?: string
}

export interface MouseAction {
  kind: 'mouse'
  button: 'left' | 'right' | 'middle' | 'back' | 'forward'
  label?: string
}

export interface MacroStep {
  keyCode: number
  flags?: ModifierFlag[]
  delayMs?: number
}

export interface MacroAction {
  kind: 'macro'
  steps: MacroStep[]
  label?: string
}

export interface LaunchAction {
  kind: 'launch'
  appName: string
  label?: string
}

export type Action = KeyAction | MouseAction | MacroAction | LaunchAction

export const TAB_FOR_KIND: Record<Action['kind'], string> = {
  key: 'Keyboard Function',
  mouse: 'Mouse Function',
  macro: 'Macro',
  launch: 'Launch',
}

const MOUSE_LABEL: Record<MouseAction['button'], string> = {
  left: 'Left Click',
  right: 'Right Click',
  middle: 'Middle Click',
  back: 'Back',
  forward: 'Forward',
}

// Short label for the mouse-diagram side panel — needs vkLabel/flagsLabel for 'key', so those
// stay call-site-provided rather than importing keycodes.ts here to avoid a circular import.
export function describeAction(action: Action, keyLabel: (a: KeyAction) => string): string {
  if (action.label?.trim()) return action.label.trim()
  switch (action.kind) {
    case 'key':
      return keyLabel(action)
    case 'mouse':
      return MOUSE_LABEL[action.button]
    case 'macro':
      return `Macro (${action.steps.length} step${action.steps.length === 1 ? '' : 's'})`
    case 'launch': {
      const base = action.appName.split('/').pop() ?? action.appName
      return base.replace(/\.app$/, '')
    }
  }
}
