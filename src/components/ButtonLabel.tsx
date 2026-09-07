import { forwardRef } from 'react'
import { flagsLabel, vkLabel } from '../lib/keycodes'
import { describeAction, type Action } from '../lib/actions'

interface ButtonLabelProps {
  number: number
  action: Action | null
  active: boolean
  align: 'left' | 'right'
  onSelect: () => void
}

export const ButtonLabel = forwardRef<HTMLButtonElement, ButtonLabelProps>(function ButtonLabel(
  { number, action, active, align, onSelect },
  ref,
) {
  const text = action
    ? describeAction(action, (key) => `${flagsLabel(key.flags)}${vkLabel(key.keyCode)}`)
    : 'Unassigned'

  const label = (
    <span
      className="text-sm font-medium truncate"
      style={{ color: active ? 'var(--accent)' : action ? 'var(--fg)' : 'var(--muted)' }}
    >
      {text}
    </span>
  )

  const badge = (
    <button
      ref={ref}
      onClick={onSelect}
      className="flex items-center justify-center w-7 h-7 shrink-0 rounded-full text-xs font-semibold transition-all"
      style={{
        background: active ? 'var(--accent)' : 'rgba(255,255,255,0.08)',
        color: active ? '#0a0a0a' : 'var(--fg)',
        border: `1px solid ${active ? 'var(--accent)' : 'var(--border)'}`,
        boxShadow: active ? '0 0 0 3px var(--accent-dim)' : 'none',
      }}
      aria-label={`Button ${number}`}
    >
      {number}
    </button>
  )

  return (
    <div
      className="flex items-center gap-2.5 cursor-pointer"
      style={{ flexDirection: align === 'left' ? 'row-reverse' : 'row' }}
      onClick={onSelect}
    >
      {badge}
      <div style={{ textAlign: align === 'left' ? 'right' : 'left', minWidth: 0 }}>{label}</div>
    </div>
  )
})
