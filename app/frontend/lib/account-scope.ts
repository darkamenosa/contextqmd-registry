function currentPath(url: string): string {
  return url.split("?")[0].split("#")[0]
}

function accountScope(url: string): string | null {
  const path = currentPath(url)
  const appPrefixMatch = path.match(/^\/app\/(\d+)(?:\/|$)/)

  if (appPrefixMatch) {
    return appPrefixMatch[1]
  }

  return null
}

function withAppPrefixAccount(path: string, account: string): string {
  if (!path.startsWith("/app")) {
    return path
  }

  if (path === "/app") {
    return `/app/${account}`
  }

  if (path === `/app/${account}` || path.startsWith(`/app/${account}/`)) {
    return path
  }

  return path.replace(/^\/app(?=\/|$)/, `/app/${account}`)
}

export function withAccountScope(
  url: string,
  path: string,
  fallbackAccount?: string | number | null
): string {
  if (!path.startsWith("/")) {
    return path
  }

  const account = accountScope(url) ?? normalizeAccountId(fallbackAccount)
  if (!account) {
    if (path.startsWith("/app/")) {
      return "/app"
    }
    return path
  }

  return withAppPrefixAccount(path, account)
}

export function withCurrentAccountScope(url: string, path: string): string {
  if (!path.startsWith("/")) {
    return path
  }

  const account = accountScope(url)
  if (!account) {
    return path
  }

  return withAppPrefixAccount(path, account)
}

function normalizeAccountId(
  account: string | number | null | undefined
): string | null {
  if (account == null) {
    return null
  }

  return account.toString()
}
