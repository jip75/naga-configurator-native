import { useState, type KeyboardEvent } from 'react'
import { CODE_TO_VK, vkLabel, flagsLabel } from '../lib/keycodes'
import type { KeyAction } from '../lib/actions'

const MODIFIER_CODES = new Set([
  'MetaLeft', 'MetaRight', 'ShiftLeft', 'ShiftRight', 'ControlLeft', 'ControlRight', 'AltLeft', 'AltRight',
])

interface ShortcutRecorderProps {
  value: KeyAction | null
  onChange: (action: KeyAction) => void
}

export function ShortcutRecorder({ value, onChange }: ShortcutRecorderProps) {
  const [recording, setRecording] = useState(false)

  function handleKeyDown(e: KeyboardEvent) {
    e.preventDefault()
    if (MODIFIER_CODES.has(e.code)) return

    const vk = CODE_TO_VK[e.code]
    if (vk === undefined) return

    const flags: KeyAction['flags'] = []
    if (e.metaKey) flags.push('cmd')
    if (e.shiftKey) flags.push('shift')
    if (e.ctrlKey) flags.push('ctrl')
    if (e.altKey) flags.push('option')

    onChange({ kind: 'key', keyCode: vk, flags })
    setRecording(false)
  }

  return (
    <button
      onClick={() => setRecording(true)}
      onKeyDown={recording ? handleKeyDown : undefined}
      onBlur={() => setRecording(false)}
      autoFocus={recording}
      className="w-full rounded-lg px-4 py-3 text-left font-mono text-sm"
      style={{
        border: `1px solid ${recording ? 'var(--accent)' : 'var(--border)'}`,
        background: recording ? 'color-mix(in srgb, var(--accent) 12%, transparent)' : 'transparent',
        color: 'var(--fg)',
      }}
    >
      {recording
        ? 'Press a key combo…'
        : value
          ? `${flagsLabel(value.flags)}${vkLabel(value.keyCode)}`
          : 'Click to record a shortcut'}
    </button>
  )
}
