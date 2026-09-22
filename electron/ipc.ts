import { ipcMain, BrowserWindow, dialog } from 'electron'
import { execFile } from 'node:child_process'
import { nagaBridge, DEFAULT_MAPPING, type ButtonMapping } from './hid-capture'

export function registerIpcHandlers() {
  nagaBridge.start()
  nagaBridge.on('error-log', (msg: string) => {
    console.error('[naga-hid-helper]', msg)
    // Previously this only went to the main process's own console — invisible in a
    // packaged app launched from Dock/tray, so a real failure (e.g. the Mission
    // Control button failing to launch) looked identical to nothing happening at
    // all. Forward it to the renderer so the user actually sees it.
    for (const win of BrowserWindow.getAllWindows()) {
      win.webContents.send('naga:error-log', msg)
    }
  })
  nagaBridge.on('ready', () => console.log('[naga-hid-helper] ready — Naga interface seized'))
  nagaBridge.on('exit', (code: number | null) => console.error('[naga-hid-helper] exited, code', code))

  nagaBridge.onButton((code) => {
    for (const win of BrowserWindow.getAllWindows()) {
      win.webContents.send('naga:button-pressed', code)
    }
  })

  ipcMain.handle('naga:list-devices', async () => {
    // No Karabiner dependency — read straight from the USB tree.
    return new Promise((resolve) => {
      execFile('system_profiler', ['SPUSBDataType', '-json'], { maxBuffer: 10 * 1024 * 1024 }, (err, stdout) => {
        if (err) return resolve([])
        try {
          const data = JSON.parse(stdout)
          const found: unknown[] = []
          const walk = (nodes: any[]) => {
            for (const node of nodes ?? []) {
              if (typeof node?.manufacturer === 'string' && node.manufacturer.includes('Razer')) {
                found.push(node)
              }
              if (Array.isArray(node?._items)) walk(node._items)
            }
          }
          walk(data.SPUSBDataType)
          resolve(found)
        } catch {
          resolve([])
        }
      })
    })
  })

  ipcMain.handle('naga:get-mapping', () => nagaBridge.getMapping())

  ipcMain.handle('naga:set-mapping', (_event, mapping: ButtonMapping) => {
    nagaBridge.setMapping(mapping)
    return true
  })

  ipcMain.handle('naga:apply', () => {
    nagaBridge.save()
    return true
  })

  ipcMain.handle('naga:pick-app', async () => {
    const result = await dialog.showOpenDialog({
      defaultPath: '/Applications',
      properties: ['openFile'],
      filters: [{ name: 'Applications', extensions: ['app'] }],
    })
    if (result.canceled || !result.filePaths[0]) return null
    return result.filePaths[0]
  })
}

export { DEFAULT_MAPPING }
