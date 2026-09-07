import type { MouseAction } from '../lib/actions'

const OPTIONS: Array<{ value: MouseAction['button']; label: string }> = [
  { value: 'left', label: 'Left Click' },
  { value: 'right', label: 'Right Click' },
  { value: 'middle', label: 'Middle Click' },
  { value: 'back', label: 'Back' },
  { value: 'forward', label: 'Forward' },
]

interface MouseFunctionEditorProps {
  value: MouseAction | null
  onChange: (action: MouseAction) => void
}

export function MouseFunctionEditor({ value, onChange }: MouseFunctionEditorProps) {
  return (
    <div className="flex flex-col gap-2">
      {OPTIONS.map((opt) => {
        const selected = value?.button === opt.value
        return (
          <button
            key={opt.value}
            onClick={() => onChange({ kind: 'mouse', button: opt.value })}
            className="w-full rounded-lg px-4 py-3 text-left text-sm"
            style={{
              border: `1px solid ${selected ? 'var(--accent)' : 'var(--border)'}`,
              background: selected ? 'color-mix(in srgb, var(--accent) 12%, transparent)' : 'transparent',
              color: selected ? 'var(--accent)' : 'var(--fg)',
            }}
          >
            {opt.label}
          </button>
        )
      })}
    </div>
  )
}
