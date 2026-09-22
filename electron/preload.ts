import { contextBridge, ipcRenderer } from 'electron'
import type { ButtonMapping } from './hid-capture'

contextBridge.exposeInMainWorld('naga', {
  listDevices: () => ipcRenderer.invoke('naga:list-devices'),
  getMapping: () => ipcRenderer.invoke('naga:get-mapping'),
  setMapping: (mapping: ButtonMapping) => ipcRenderer.invoke('naga:set-mapping', mapping),
  apply: () => ipcRenderer.invoke('naga:apply'),
  pickApp: () => ipcRenderer.invoke('naga:pick-app') as Promise<string | null>,
  onButtonPressed: (cb: (buttonNumber: number) => void) => {
    ipcRenderer.on('naga:button-pressed', (_event, buttonNumber: number) => cb(buttonNumber))
  },
  onError: (cb: (message: string) => void) => {
    ipcRenderer.on('naga:error-log', (_event, message: string) => cb(message))
  },
})
