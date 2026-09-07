import { app, BrowserWindow, Menu, Tray } from 'electron'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { registerIpcHandlers } from './ipc'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const isDev = !app.isPackaged

app.setName('Naga Configurator')

let win: BrowserWindow | null = null
let tray: Tray | null = null
let isQuitting = false

function createWindow() {
  win = new BrowserWindow({
    width: 1100,
    height: 760,
    title: 'Naga Configurator',
    webPreferences: {
      preload: path.join(__dirname, 'preload.mjs'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  })

  if (isDev && process.env.VITE_DEV_SERVER_URL) {
    win.loadURL(process.env.VITE_DEV_SERVER_URL)
  } else {
    win.loadFile(path.join(__dirname, '../dist/index.html'))
  }

  // Keep the app reachable from the tray instead of quitting when the
  // window is closed — the tray icon is the whole point (easy to find).
  win.on('close', (event) => {
    if (isQuitting) return
    event.preventDefault()
    win?.hide()
  })
}

function showWindow() {
  if (!win || win.isDestroyed()) {
    createWindow()
    return
  }
  win.show()
  win.focus()
}

function createTray() {
  tray = new Tray(path.join(__dirname, '../assets/tray/icon.png'))
  tray.setToolTip('Naga Configurator (Left-Handed)')
  tray.setContextMenu(
    Menu.buildFromTemplate([
      { label: 'Open Naga Configurator', click: showWindow },
      { type: 'separator' },
      {
        label: 'Quit',
        click: () => {
          isQuitting = true
          app.quit()
        },
      },
    ]),
  )
  tray.on('click', showWindow)
}

app.whenReady().then(() => {
  registerIpcHandlers()
  createWindow()
  createTray()

  app.on('activate', showWindow)
})

app.on('before-quit', () => {
  isQuitting = true
})

app.on('window-all-closed', () => {
  // Tray keeps the app alive on macOS by design; on other platforms,
  // there's no tray fallback here, so quit as usual.
  if (process.platform !== 'darwin') app.quit()
})
