import { useEffect, useState } from 'react'
import { MouseDiagram } from './components/MouseDiagram'
import { SidePanel } from './components/SidePanel'
import { TopBar } from './components/TopBar'
import type { Action } from './lib/actions'
import device from './devices/naga-left-handed.json'

declare global {
  interface Window {
    naga: {
      listDevices: () => Promise<unknown[]>
      getMapping: () => Promise<Record<string, Action>>
      setMapping: (mapping: Record<string, Action>) => Promise<boolean>
      apply: () => Promise<boolean>
      pickApp: () => Promise<string | null>
      onButtonPressed: (cb: (rawCode: string) => void) => void
    }
  }
}

function App() {
  const [selected, setSelected] = useState<number | null>(null)
  const [mapping, setMapping] = useState<Record<string, Action>>({})
  const [lastFired, setLastFired] = useState<number | null>(null)
  const [saveState, setSaveState] = useState<'idle' | 'saving' | 'saved'>('idle')

  useEffect(() => {
    window.naga?.getMapping().then(setMapping)
    window.naga?.onButtonPressed((rawCode) => {
      const button = device.buttons.find((b) => b.rawCode === rawCode)
      if (button) {
        setLastFired(button.number)
        setTimeout(() => setLastFired(null), 400)
      }
    })
  }, [])

  const selectedButton = device.buttons.find((b) => b.number === selected)
  const selectedAction = selectedButton ? (mapping[selectedButton.rawCode] ?? null) : null

  function handleActionChange(action: Action) {
    if (!selectedButton) return
    const next = { ...mapping, [selectedButton.rawCode]: action }
    setMapping(next)
    window.naga?.setMapping(next)
    setSaveState('idle')
  }

  async function handleSave() {
    setSaveState('saving')
    await window.naga?.apply()
    setSaveState('saved')
    setTimeout(() => setSaveState('idle'), 1500)
  }

  return (
    <div className="min-h-screen flex flex-col items-center">
      <TopBar deviceName={device.displayName} saveState={saveState} onSave={handleSave} />

      <div className="flex-1 w-full flex flex-col items-center justify-center gap-6 px-10 pb-10">
        <MouseDiagram
          device={device}
          selected={lastFired ?? selected}
          mapping={mapping}
          onSelect={setSelected}
        />
        <SidePanel buttonNumber={selected} action={selectedAction} onChange={handleActionChange} />
      </div>
    </div>
  )
}

export default App
