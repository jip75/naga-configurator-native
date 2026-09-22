import { useRef, useState, type KeyboardEvent } from 'react'
import { CODE_TO_VK, vkLabel, flagsLabel } from '../lib/keycodes'
import type { MacroAction, MacroStep } from '../lib/actions'

const MODIFIER_CODES = new Set([
  'MetaLeft', 'MetaRight', 'ShiftLeft', 'ShiftRight', 'ControlLeft', 'ControlRight', 'AltLeft', 'AltRight',
])

interface MacroRecorderProps {
  value: MacroAction | null
  onChange: (action: MacroAction) => void
}

export function MacroRecorder({ value, onChange }: MacroRecorderProps) {
  const [recording, setRecording] = useState(false)
  const [steps, setSteps] = useState<MacroStep[]>(value?.steps ?? [])
  const lastTimeRef = useRef(0)

  function startRecording() {
    setSteps([])
    lastTimeRef.current = performance.now()
    setRecording(true)
  }

  function stopRecording() {
    setRecording(false)
    // Stopping before any key was pressed (e.g. clicking away by accident)
    // must not save an empty macro — it would look configured but silently
    // do nothing on every press, with no error to explain why.
    if (steps.length === 0) return
    onChange({ kind: 'macro', steps })
  }

  function removeStep(i: number) {
    const next = steps.filter((_, idx) => idx !== i)
    setSteps(next)
    onChange({ kind: 'macro', steps: next })
  }

  function handleKeyDown(e: KeyboardEvent) {
    e.preventDefault()
    if (MODIFIER_CODES.has(e.code)) return
    const vk = CODE_TO_VK[e.code]
    if (vk === undefined) return

    const flags: MacroStep['flags'] = []
    if (e.metaKey) flags.push('cmd')
    if (e.shiftKey) flags.push('shift')
    if (e.ctrlKey) flags.push('ctrl')
    if (e.altKey) flags.push('option')

    const now = performance.now()
    const delayMs = steps.length === 0 ? undefined : Math.min(Math.round(now - lastTimeRef.current), 2000)
    lastTimeRef.current = now
    setSteps((prev) => [...prev, { keyCode: vk, flags, delayMs }])
  }

  return (
    <div className="flex flex-col gap-3">
      <button
        onClick={recording ? stopRecording : startRecording}
        onKeyDown={recording ? handleKeyDown : undefined}
        autoFocus={recording}
        onBlur={() => recording && stopRecording()}
        className="w-full rounded-lg px-4 py-3 text-left text-sm font-mono"
        style={{
          border: `1px solid ${recording ? 'var(--accent)' : 'var(--border)'}`,
          background: recording ? 'color-mix(in srgb, var(--accent) 12%, transparent)' : 'transparent',
          color: 'var(--fg)',
        }}
      >
        {recording ? 'Recording… press keys, click away to stop' : 'Click to record a macro'}
      </button>

      {steps.length > 0 && (
        <div className="flex flex-col gap-1">
          {steps.map((step, i) => (
            <div
              key={i}
              className="flex items-center justify-between rounded-lg px-3 py-2 text-xs font-mono"
              style={{ background: 'color-mix(in srgb, var(--fg) 5%, transparent)' }}
            >
              <span>
                {i + 1}. {flagsLabel(step.flags)}
                {vkLabel(step.keyCode)}
                {step.delayMs !== undefined && (
                  <span style={{ color: 'var(--muted)' }}> · +{step.delayMs}ms</span>
                )}
              </span>
              {!recording && (
                <button onClick={() => removeStep(i)} style={{ color: 'var(--muted)' }} aria-label="Remove step">
                  ✕
                </button>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
