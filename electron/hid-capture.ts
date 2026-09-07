import { spawn, execFile, ChildProcessWithoutNullStreams } from 'node:child_process'
import path from 'node:path'
import fs from 'node:fs'
import { EventEmitter } from 'node:events'
import { app } from 'electron'

// Bridges to electron/native/naga-hid-helper (Swift): captures the Naga's raw button
// codes via IOHIDManager and injects the mapped output via CGEventPost. Replaces
// Karabiner-Elements entirely — no driver/system extension involved on either side.

export type RawButtonCode = '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9' | '0' | '-' | '='

export type ModifierFlag = 'cmd' | 'shift' | 'ctrl' | 'option'

export interface KeyAction {
  kind: 'key'
  keyCode: number
  flags?: ModifierFlag[]
  extraKeyDown?: number
  extraKeyUp?: number
  system?: boolean // route through osascript/Accessibility — for system-reserved shortcuts CGEventPost can't reach
  label?: string // user-chosen display name, overrides the auto-derived description
}

export interface MouseAction {
  kind: 'mouse'
  button: 'left' | 'right' | 'middle' | 'back' | 'forward'
  label?: string
}

export interface MacroStep {
  keyCode: number
  flags?: ModifierFlag[]
  delayMs?: number // pause AFTER this step, before the next one fires
}

export interface MacroAction {
  kind: 'macro'
  steps: MacroStep[]
  label?: string
}

export interface LaunchAction {
  kind: 'launch'
  appName: string // passed to `open -a` — accepts a display name ("Mission Control") or a full .app path
  label?: string
}

export type InjectAction = KeyAction | MouseAction | MacroAction | LaunchAction

export type ButtonMapping = Record<RawButtonCode, InjectAction>

// macOS virtual key codes (stable ANSI keyboard layout constants).
const VK = {
  A: 0x00, C: 0x08, V: 0x09,
  RETURN: 0x24, SPACE: 0x31, DELETE: 0x33, ESCAPE: 0x35,
  RIGHT_SHIFT: 0x3c,
  LEFT: 0x7b, RIGHT: 0x7c, DOWN: 0x7d, UP: 0x7e,
} as const

// Seeded from the user's working right-handed Naga Pro V2 Synapse profile.
export const DEFAULT_MAPPING: ButtonMapping = {
  '1': { kind: 'key', keyCode: VK.C, flags: ['cmd'] },                     // Cmd+C
  '2': { kind: 'key', keyCode: VK.V, flags: ['cmd'] },                     // Cmd+V
  '3': { kind: 'key', keyCode: VK.A, flags: ['cmd'] },                     // Cmd+A
  '4': { kind: 'key', keyCode: VK.LEFT },
  '5': { kind: 'key', keyCode: VK.DOWN },
  '6': { kind: 'key', keyCode: VK.RIGHT },
  '7': { kind: 'key', keyCode: VK.DELETE },
  '8': { kind: 'key', keyCode: VK.RETURN, flags: ['shift'], extraKeyDown: VK.RIGHT_SHIFT, extraKeyUp: VK.RIGHT_SHIFT },
  '9': { kind: 'key', keyCode: VK.ESCAPE },
  '0': { kind: 'launch', appName: 'Mission Control' },                     // sidesteps the AppleEvents/TCC mess entirely
  '-': { kind: 'key', keyCode: VK.SPACE },
  '=': { kind: 'key', keyCode: VK.RETURN },
}

type ButtonListener = (code: RawButtonCode) => void

// Saved mapping lives in userData, not the app bundle, so it survives updates/reinstalls.
function mappingFilePath(): string {
  return path.join(app.getPath('userData'), 'mapping.json')
}

// Pre-'kind' saves on disk are bare key actions — stamp them so old mapping.json files
// (and anything a future format change forgets to tag) still dispatch correctly.
function normalizeAction(a: any): InjectAction {
  if (a && typeof a === 'object' && !a.kind && typeof a.keyCode === 'number') {
    return { kind: 'key', ...a }
  }
  return a
}

function loadMapping(): ButtonMapping {
  try {
    const raw = fs.readFileSync(mappingFilePath(), 'utf8')
    const merged: ButtonMapping = { ...DEFAULT_MAPPING, ...JSON.parse(raw) }
    for (const code of Object.keys(merged) as RawButtonCode[]) {
      merged[code] = normalizeAction(merged[code])
    }
    return merged
  } catch {
    return DEFAULT_MAPPING
  }
}

export class NagaBridge extends EventEmitter {
  private proc: ChildProcessWithoutNullStreams | null = null
  private mapping: ButtonMapping = loadMapping()
  private buffer = ''

  start() {
    if (this.proc) return
    // Dev: helper lives under the project's electron/native/. Packaged builds will
    // ship it as an extraResource (Phase 4) and this path swaps to process.resourcesPath.
    const helperPath = app.isPackaged
      ? path.join(process.resourcesPath, 'native', 'naga-hid-helper')
      : path.join(app.getAppPath(), 'electron', 'native', 'naga-hid-helper')
    this.proc = spawn(helperPath, [], { stdio: 'pipe' })

    this.proc.stdout.on('data', (chunk: Buffer) => {
      this.buffer += chunk.toString('utf8')
      let newlineIndex: number
      while ((newlineIndex = this.buffer.indexOf('\n')) !== -1) {
        const line = this.buffer.slice(0, newlineIndex)
        this.buffer = this.buffer.slice(newlineIndex + 1)
        this.handleLine(line)
      }
    })

    this.proc.stderr.on('data', (chunk: Buffer) => {
      this.emit('error-log', chunk.toString('utf8').trim())
    })

    this.proc.on('exit', (code) => {
      this.emit('exit', code)
      this.proc = null
    })
  }

  stop() {
    this.proc?.kill()
    this.proc = null
  }

  setMapping(mapping: ButtonMapping) {
    this.mapping = mapping
  }

  getMapping(): ButtonMapping {
    return this.mapping
  }

  save() {
    fs.mkdirSync(path.dirname(mappingFilePath()), { recursive: true })
    fs.writeFileSync(mappingFilePath(), JSON.stringify(this.mapping, null, 2))
  }

  onButton(listener: ButtonListener) {
    this.on('button', listener)
  }

  private handleLine(line: string) {
    if (!line.trim()) return
    let msg: { type: string; code?: string }
    try {
      msg = JSON.parse(line)
    } catch {
      return
    }

    if (msg.type === 'ready') {
      this.emit('ready')
      return
    }

    if (msg.type === 'button' && msg.code) {
      const code = msg.code as RawButtonCode
      this.emit('button', code)
      const action = this.mapping[code]
      if (action) this.dispatch(action)
    }
  }

  private dispatch(action: InjectAction) {
    switch (action.kind) {
      case 'launch':
        this.injectLaunch(action)
        break
      case 'mouse':
        this.injectMouse(action)
        break
      case 'macro':
        this.injectMacro(action)
        break
      case 'key':
        if (action.system) this.injectSystemShortcut(action)
        else this.inject(action)
        break
    }
  }

  private inject(step: { keyCode: number; flags?: ModifierFlag[]; extraKeyDown?: number; extraKeyUp?: number }) {
    this.proc?.stdin.write(JSON.stringify(step) + '\n')
  }

  private injectMouse(action: MouseAction) {
    this.proc?.stdin.write(JSON.stringify({ mouse: action.button }) + '\n')
  }

  private injectMacro(action: MacroAction) {
    const run = (i: number) => {
      if (i >= action.steps.length) return
      const step = action.steps[i]
      this.inject(step)
      setTimeout(() => run(i + 1), step.delayMs ?? 60)
    }
    run(0)
  }

  private injectLaunch(action: LaunchAction) {
    execFile('/usr/bin/open', ['-a', action.appName], (err) => {
      if (err) this.emit('error-log', `launch failed for "${action.appName}": ${err.message}`)
    })
  }

  // Available fallback for a 'key' action explicitly marked system:true — CGEventPost can't
  // reach system-reserved shortcuts (Mission Control, Spaces), only System Events GUI scripting
  // can, which needs Automation/AppleEvents consent from this registered .app. Not used by the
  // default mapping (button 10 is 'launch' now — simpler, no TCC dance at all).
  private static readonly SYSTEM_MODIFIER_PHRASE: Record<string, string> = {
    cmd: 'command down', shift: 'shift down', ctrl: 'control down', alt: 'option down', option: 'option down',
  }

  private injectSystemShortcut(action: KeyAction) {
    const mods = (action.flags ?? []).map((f) => NagaBridge.SYSTEM_MODIFIER_PHRASE[f]).filter(Boolean)
    const modClause = mods.length ? ` using {${mods.join(', ')}}` : ''
    const script = `tell application "System Events" to key code ${action.keyCode}${modClause}`
    execFile('/usr/bin/osascript', ['-e', script], (err) => {
      if (err) this.emit('error-log', `system-shortcut inject failed: ${err.message}`)
    })
  }
}

export const nagaBridge = new NagaBridge()
