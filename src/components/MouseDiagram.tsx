import { useLayoutEffect, useRef, useState } from 'react'
import mouseImage from '../assets/naga-left-handed-cutout.png'
import { Hotspot } from './Hotspot'
import { ButtonLabel } from './ButtonLabel'
import type { Action } from '../lib/actions'
import type deviceRaw from '../devices/naga-left-handed.json'

type Device = typeof deviceRaw

interface MouseDiagramProps {
  device: Device
  selected: number | null
  mapping: Record<string, Action>
  onSelect: (buttonNumber: number) => void
}

interface Line {
  number: number
  x1: number
  y1: number
  x2: number
  y2: number
}

export function MouseDiagram({ device, selected, mapping, onSelect }: MouseDiagramProps) {
  const stageRef = useRef<HTMLDivElement>(null)
  const imgRef = useRef<HTMLImageElement>(null)
  const badgeRefs = useRef<Record<number, HTMLButtonElement | null>>({})
  const [box, setBox] = useState({ w: 0, h: 0 })
  const [lines, setLines] = useState<Line[]>([])

  const left = device.buttons.filter((b) => b.number <= 6)
  const right = device.buttons.filter((b) => b.number > 6)

  useLayoutEffect(() => {
    function measure() {
      const stage = stageRef.current
      const img = imgRef.current
      if (!stage || !img) return
      const stageRect = stage.getBoundingClientRect()
      const imgRect = img.getBoundingClientRect()
      setBox({ w: stageRect.width, h: stageRect.height })

      const next: Line[] = device.buttons.map((b) => {
        const badge = badgeRefs.current[b.number]
        const badgeRect = badge?.getBoundingClientRect()
        const x2 = imgRect.left - stageRect.left + (b.x / 100) * imgRect.width
        const y2 = imgRect.top - stageRect.top + (b.y / 100) * imgRect.height
        const onLeft = b.number <= 6
        const x1 = badgeRect ? (onLeft ? badgeRect.right : badgeRect.left) - stageRect.left : x2
        const y1 = badgeRect ? badgeRect.top + badgeRect.height / 2 - stageRect.top : y2
        return { number: b.number, x1, y1, x2, y2 }
      })
      setLines(next)
    }

    measure()
    const ro = new ResizeObserver(measure)
    if (stageRef.current) ro.observe(stageRef.current)
    window.addEventListener('resize', measure)
    return () => {
      ro.disconnect()
      window.removeEventListener('resize', measure)
    }
  }, [device])

  return (
    <div ref={stageRef} className="relative w-full max-w-4xl flex items-center justify-center gap-6 py-8">
      <svg
        className="absolute inset-0 pointer-events-none"
        width={box.w}
        height={box.h}
        style={{ overflow: 'visible' }}
      >
        {lines.map((l) => (
          <line
            key={l.number}
            x1={l.x1}
            y1={l.y1}
            x2={l.x2}
            y2={l.y2}
            stroke={selected === l.number ? 'var(--accent)' : 'rgba(255,255,255,0.18)'}
            strokeWidth={selected === l.number ? 1.5 : 1}
          />
        ))}
      </svg>

      <div className="flex flex-col gap-5 w-40 shrink-0 z-10">
        {left.map((b) => (
          <ButtonLabel
            key={b.number}
            ref={(el) => {
              badgeRefs.current[b.number] = el
            }}
            number={b.number}
            action={mapping[b.rawCode] ?? null}
            active={selected === b.number}
            align="left"
            onSelect={() => onSelect(b.number)}
          />
        ))}
      </div>

      <div className="relative shrink-0" style={{ height: 420 }}>
        <img
          ref={imgRef}
          src={mouseImage}
          alt={device.displayName}
          draggable={false}
          className="h-full w-auto select-none relative z-10"
          style={{
            filter:
              'drop-shadow(0 0 6px var(--accent)) drop-shadow(0 0 22px var(--accent-dim)) drop-shadow(0 0 46px var(--accent-dim))',
          }}
        />
        {device.buttons.map((button) => (
          <Hotspot
            key={button.number}
            number={button.number}
            x={button.x}
            y={button.y}
            active={selected === button.number}
            onSelect={() => onSelect(button.number)}
          />
        ))}
      </div>

      <div className="flex flex-col gap-5 w-40 shrink-0 z-10">
        {right.map((b) => (
          <ButtonLabel
            key={b.number}
            ref={(el) => {
              badgeRefs.current[b.number] = el
            }}
            number={b.number}
            action={mapping[b.rawCode] ?? null}
            active={selected === b.number}
            align="right"
            onSelect={() => onSelect(b.number)}
          />
        ))}
      </div>
    </div>
  )
}
