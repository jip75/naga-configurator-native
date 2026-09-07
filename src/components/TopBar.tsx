import shamrock from '../assets/shamrock.png'

const TABS = ['Customize', 'Performance', 'Scrolling', 'Lighting', 'Power'] as const

type SaveState = 'idle' | 'saving' | 'saved'

interface TopBarProps {
  deviceName: string
  saveState: SaveState
  onSave: () => void
}

export function TopBar({ deviceName, saveState, onSave }: TopBarProps) {
  return (
    <div className="w-full flex items-center justify-between px-6 py-3" style={{ borderBottom: '1px solid var(--border)' }}>
      <div className="flex items-center gap-2.5">
        <img src={shamrock} alt="MkrLab" className="w-6 h-6 object-contain" />
        <div className="flex flex-col leading-none">
          <span className="text-sm font-semibold tracking-wide">NAGA CONFIGURATOR</span>
          <span className="text-[11px] opacity-40 mt-0.5">{deviceName}</span>
        </div>
      </div>

      <div className="flex items-center gap-1">
        {TABS.map((tab, i) => (
          <div
            key={tab}
            className="px-3.5 py-1.5 rounded-full text-xs font-semibold uppercase tracking-wide"
            style={{
              background: i === 0 ? 'var(--accent)' : 'transparent',
              color: i === 0 ? '#0a0a0a' : 'var(--muted)',
              cursor: i === 0 ? 'default' : 'not-allowed',
            }}
            title={i === 0 ? undefined : 'Coming soon'}
          >
            {tab}
          </div>
        ))}
      </div>

      <button
        onClick={onSave}
        disabled={saveState !== 'idle'}
        className="w-24 px-3.5 py-1.5 rounded-full text-xs font-semibold uppercase tracking-wide"
        style={{
          background: saveState === 'saved' ? 'transparent' : 'var(--accent)',
          color: saveState === 'saved' ? 'var(--accent)' : '#0a0a0a',
          border: saveState === 'saved' ? '1px solid var(--accent)' : 'none',
          opacity: saveState === 'saving' ? 0.6 : 1,
        }}
      >
        {saveState === 'saving' ? 'Saving…' : saveState === 'saved' ? 'Saved ✓' : 'Save'}
      </button>
    </div>
  )
}
