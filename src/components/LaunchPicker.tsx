import type { LaunchAction } from '../lib/actions'

interface LaunchPickerProps {
  value: LaunchAction | null
  onChange: (action: LaunchAction) => void
}

function displayName(appName: string): string {
  const base = appName.split('/').pop() ?? appName
  return base.replace(/\.app$/, '')
}

export function LaunchPicker({ value, onChange }: LaunchPickerProps) {
  async function browse() {
    const picked = await window.naga?.pickApp()
    if (picked) onChange({ kind: 'launch', appName: picked })
  }

  return (
    <div className="flex flex-col gap-2">
      <input
        type="text"
        value={value ? displayName(value.appName) : ''}
        onChange={(e) => onChange({ kind: 'launch', appName: e.target.value })}
        placeholder="Application name (e.g. Mission Control)"
        className="w-full rounded-lg px-4 py-3 text-sm"
        style={{ border: '1px solid var(--border)', background: 'transparent', color: 'var(--fg)' }}
      />
      <button
        onClick={browse}
        className="w-full rounded-lg px-4 py-2 text-sm"
        style={{ border: '1px solid var(--border)', color: 'var(--muted)' }}
      >
        Browse Applications…
      </button>
    </div>
  )
}
