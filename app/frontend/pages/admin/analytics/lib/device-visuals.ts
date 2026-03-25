const BROWSER_ICONS: Record<string, string> = {
  Chrome: "chrome.svg",
  curl: "curl.svg",
  Safari: "safari.png",
  Firefox: "firefox.svg",
  "Microsoft Edge": "edge.svg",
  Edge: "edge.svg",
  Vivaldi: "vivaldi.svg",
  Opera: "opera.svg",
  "Samsung Browser": "samsung-internet.svg",
  Chromium: "chromium.svg",
  "UC Browser": "uc.svg",
  "Yandex Browser": "yandex.png",
  "DuckDuckGo Privacy Browser": "duckduckgo.svg",
  Brave: "brave.svg",
  Ecosia: "ecosia.png",
  "MIUI Browser": "miui.webp",
  "Huawei Browser Mobile": "huawei.png",
  "QQ Browser": "qq.png",
  "vivo Browser": "vivo.png",
}

const OS_ICONS: Record<string, string> = {
  iOS: "ios.png",
  Mac: "mac.png",
  macOS: "mac.png",
  Windows: "windows.png",
  "Windows Phone": "windows.png",
  Android: "android.png",
  "GNU/Linux": "gnu_linux.png",
  Linux: "gnu_linux.png",
  Ubuntu: "ubuntu.png",
  "Chrome OS": "chrome_os.png",
  iPadOS: "ipad_os.png",
  "Fire OS": "fire_os.png",
  HarmonyOS: "harmony_os.png",
  Tizen: "tizen.png",
  PlayStation: "playstation.png",
  KaiOS: "kai_os.png",
  Fedora: "fedora.png",
  FreeBSD: "freebsd.png",
}

export function getBrowserIcon(name: string): string {
  const baseName = name.split(/\s+\d/)[0].trim()

  if (BROWSER_ICONS[baseName]) {
    return BROWSER_ICONS[baseName]
  }

  for (const [browserName, filename] of Object.entries(BROWSER_ICONS)) {
    if (name.toLowerCase().includes(browserName.toLowerCase())) {
      return filename
    }
  }

  return "fallback.svg"
}

export function getOSIcon(name: string): string {
  const baseName = name.split(/\s+\d/)[0].trim()

  if (OS_ICONS[baseName]) {
    return OS_ICONS[baseName]
  }

  for (const [osName, filename] of Object.entries(OS_ICONS)) {
    if (name.toLowerCase().includes(osName.toLowerCase())) {
      return filename
    }
  }

  return "fallback.svg"
}

export function categorizeScreenSize(screenSize: string): string {
  if (["Mobile", "Tablet", "Laptop", "Desktop"].includes(screenSize)) {
    return screenSize
  }

  const match = screenSize.match(/(\d+)x(\d+)/)
  if (!match) return "Desktop"

  const width = parseInt(match[1], 10)

  if (width < 576) return "Mobile"
  if (width < 992) return "Tablet"
  if (width < 1440) return "Laptop"
  return "Desktop"
}
