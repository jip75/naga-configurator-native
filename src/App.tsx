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
      onError: (cb: (message: string) => void) => void
    }
  }
}

function App() {
  const [selected, setSelected] = useState<number | null>(null)
  const [mapping, setMapping] = useState<Record<string, Action>>({})
  const [lastFired, setLastFired] = useState<number | null>(null)
  const [saveState, setSaveState] = useState<'idle' | 'saving' | 'saved'>('idle')
  const [errorMessage, setErrorMessage] = useState<string | null>(null)

  useEffect(() => {
    window.naga?.getMapping().then(setMapping)
    window.naga?.onButtonPressed((rawCode) => {
      const button = device.buttons.find((b) => b.rawCode === rawCode)
      if (button) {
        setLastFired(button.number)
        setTimeout(() => setLastFired(null), 400)
      }
    })
    window.naga?.onError((message) => setErrorMessage(message))
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

      {errorMessage && (
        <div
          role="alert"
          className="fixed bottom-6 left-1/2 -translate-x-1/2 max-w-[90vw] rounded-lg px-4 py-3 text-sm font-mono flex items-center gap-3"
          style={{ background: '#2a1414', border: '1px solid #ff5c5c66', color: '#ff9d9d', boxShadow: '0 10px 30px rgba(0,0,0,0.5)' }}
        >
          <span>{errorMessage}</span>
          <button onClick={() => setErrorMessage(null)} style={{ color: '#ff9d9d' }} aria-label="Dismiss">
            ✕
          </button>
        </div>
      )}
    </div>
  )
}

export default App
