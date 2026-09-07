interface HotspotProps {
  number: number
  x: number
  y: number
  active: boolean
  onSelect: () => void
}

export function Hotspot({ number, x, y, active, onSelect }: HotspotProps) {
  return (
    <button
      onClick={onSelect}
      className="absolute -translate-x-1/2 -translate-y-1/2 rounded-full flex items-center justify-center cursor-pointer z-20"
      style={{ left: `${x}%`, top: `${y}%`, width: 24, height: 24 }}
      aria-label={`Button ${number}`}
    >
      <span
        className="rounded-full transition-all block pointer-events-none"
        style={{
          width: active ? 12 : 8,
          height: active ? 12 : 8,
          background: active ? 'var(--accent)' : 'rgba(255,255,255,0.55)',
          boxShadow: active ? '0 0 8px 2px var(--accent-dim)' : 'none',
        }}
      />
    </button>
  )
}
