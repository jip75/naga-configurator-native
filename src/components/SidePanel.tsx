import { useEffect, useState } from 'react'
import { ShortcutRecorder } from './ShortcutRecorder'
import { MouseFunctionEditor } from './MouseFunctionEditor'
import { MacroRecorder } from './MacroRecorder'
import { LaunchPicker } from './LaunchPicker'
import type { Action } from '../lib/actions'

const TABS = ['Keyboard Function', 'Mouse Function', 'Macro', 'Launch'] as const
type Tab = (typeof TABS)[number]

const TAB_FOR_KIND: Record<Action['kind'], Tab> = {
  key: 'Keyboard Function',
  mouse: 'Mouse Function',
  macro: 'Macro',
  launch: 'Launch',
}

interface SidePanelProps {
  buttonNumber: number | null
  action: Action | null
  onChange: (action: Action) => void
}

export function SidePanel({ buttonNumber, action, onChange }: SidePanelProps) {
  const [tab, setTab] = useState<Tab>(action ? TAB_FOR_KIND[action.kind] : 'Keyboard Function')

  // Jumping to a different button should show that button's own current tab, not carry over
  // whichever tab was open for the last one.
  useEffect(() => {
    setTab(action ? TAB_FOR_KIND[action.kind] : 'Keyboard Function')
  }, [buttonNumber])

  if (buttonNumber === null) {
    return (
      <div className="text-sm px-6 py-4" style={{ color: 'var(--muted)' }}>
        Select a button to configure it
      </div>
    )
  }

  return (
    <div
      className="w-full max-w-md rounded-2xl p-5 flex flex-col gap-4"
      style={{ background: 'var(--panel)', border: '1px solid var(--border)' }}
    >
      <div className="flex items-center gap-3">
        <div
          className="flex items-center justify-center w-9 h-9 rounded-full text-sm font-bold shrink-0"
          style={{ background: 'var(--accent)', color: '#0a0a0a' }}
        >
          {buttonNumber}
        </div>
        <input
          type="text"
          value={action?.label ?? ''}
          onChange={(e) => action && onChange({ ...action, label: e.target.value })}
          placeholder="Name this button (optional)"
          className="flex-1 min-w-0 rounded-lg px-2.5 py-1.5 text-sm"
          style={{ background: 'var(--bg)', border: '1px solid var(--border)', color: 'var(--fg)' }}
        />
      </div>

      <div className="flex items-center gap-3">
        <div className="flex gap-1 text-xs flex-1">
          {TABS.map((t) => (
            <button
              key={t}
              onClick={() => setTab(t)}
              className="rounded-full px-2.5 py-1 whitespace-nowrap"
              style={{
                background: t === tab ? 'color-mix(in srgb, var(--accent) 16%, transparent)' : 'transparent',
                color: t === tab ? 'var(--accent)' : 'var(--muted)',
              }}
            >
              {t}
            </button>
          ))}
        </div>
      </div>

      <div className="flex flex-col gap-2">
        <div className="text-xs uppercase tracking-wide" style={{ color: 'var(--muted)' }}>
          Assigned {tab === 'Keyboard Function' ? 'shortcut' : tab === 'Mouse Function' ? 'click' : tab === 'Macro' ? 'sequence' : 'application'}
        </div>

        {tab === 'Keyboard Function' && (
          <ShortcutRecorder
            value={action?.kind === 'key' ? action : null}
            onChange={onChange}
          />
        )}
        {tab === 'Mouse Function' && (
          <MouseFunctionEditor
            value={action?.kind === 'mouse' ? action : null}
            onChange={onChange}
          />
        )}
        {tab === 'Macro' && (
          <MacroRecorder
            value={action?.kind === 'macro' ? action : null}
            onChange={onChange}
          />
        )}
        {tab === 'Launch' && (
          <LaunchPicker
            value={action?.kind === 'launch' ? action : null}
            onChange={onChange}
          />
        )}
      </div>
    </div>
  )
}
