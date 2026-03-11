// Flash data from Rails flash messages
export type FlashData = {
  notice?: string
  alert?: string
  success?: string
  warning?: string
  info?: string
}

// Current authenticated user (shared via Inertia)
export type CurrentUser = {
  id: number
  name: string
  email: string
  role: string | null
  staff: boolean
  accountId: number | null
  accountName: string | null
}

export type CurrentIdentity = {
  id: number
  name: string | null
  email: string
  staff: boolean
  defaultAccountId: number | null
  defaultAccountName: string | null
  defaultAccountRole: string | null
}

// Shared props available on every Inertia page
export type SharedProps = {
  flash?: FlashData
  currentUser?: CurrentUser | null
  currentIdentity?: CurrentIdentity | null
}

// Pagination data from Pagy (via pagination_props helper)
export type PaginationData = {
  page: number
  perPage: number
  total: number
  pages: number
  from: number
  to: number
  hasPrevious: boolean
  hasNext: boolean
}

// Access token types
export type AccessToken = {
  id: number
  name: string
  permission: "read" | "write"
  tokenPrefix: string | null
  createdAt: string
  lastUsedAt: string | null
}

// Admin library types
export type AdminLibrary = {
  id: number
  namespace: string
  name: string
  displayName: string
  homepageUrl: string | null
  defaultVersion: string | null
  licenseStatus: string | null
  versionCount: number
  pageCount: number
  accountName: string
  updatedAt: string
  createdAt: string
}

export type CrawlRules = {
  gitIncludePrefixes?: string[]
  gitIncludeBasenames?: string[]
  gitExcludePrefixes?: string[]
  gitExcludeBasenames?: string[]
  websiteExcludePathPrefixes?: string[]
}

export type AdminLibraryDetail = {
  id: number
  namespace: string
  name: string
  displayName: string
  homepageUrl: string | null
  defaultVersion: string | null
  sourceType: string | null
  aliases: string[]
  licenseStatus: string | null
  accountName: string
  versionCount: number
  pageCount: number
  lastCrawlUrl: string | null
  crawlRules: CrawlRules
  createdAt: string
  updatedAt: string
}

export type AdminLibraryVersion = {
  id: number
  version: string
  channel: string
  generatedAt: string | null
  pageCount: number
  createdAt: string
}

export type AdminPage = {
  id: number
  pageUid: string
  path: string
  title: string
  bytes: number
  createdAt: string
}

export type AdminCrawlItem = {
  id: number
  url: string
  sourceType: string
  status: string
  errorMessage: string | null
  createdAt: string
}

// Admin proxy config types
export type AdminProxyConfig = {
  id: number
  name: string
  scheme: string
  host: string
  port: number
  kind: string | null
  usageScope: string
  priority: number
  active: boolean
  consecutiveFailures: number
  cooldownUntil: string | null
  lastSuccessAt: string | null
  lastFailureAt: string | null
  activeLeaseCount: number
  maxConcurrency: number
  provider: string | null
  updatedAt: string
}

export type AdminProxyConfigDetail = {
  id: number
  name: string
  scheme: string
  host: string
  port: number
  username: string | null
  kind: string | null
  usageScope: string
  priority: number
  active: boolean
  maxConcurrency: number
  leaseTtlSeconds: number
  supportsStickySessions: boolean
  consecutiveFailures: number
  cooldownUntil: string | null
  lastSuccessAt: string | null
  lastFailureAt: string | null
  lastErrorClass: string | null
  lastTargetHost: string | null
  disabledReason: string | null
  provider: string | null
  notes: string | null
  activeLeaseCount: number
  createdAt: string
  updatedAt: string
}

export type AdminProxyLease = {
  id: number
  sessionKey: string
  usageScope: string
  targetHost: string | null
  stickySession: boolean
  active: boolean
  expiresAt: string
  lastSeenAt: string
  releasedAt: string | null
  createdAt: string
}

// Admin user types
export type AdminUser = {
  id: number
  email: string
  name: string | null
  authMethod: string
  staff: boolean
  status: string
  accountsCount: number
  createdAt: string
}

export type AdminUserDetail = {
  id: number
  email: string
  name: string | null
  authMethod: string
  staff: boolean
  status: string
  suspendedAt: string | null
  createdAt: string
  memberships: AdminUserMembership[]
}

export type AdminUserMembership = {
  id: number
  accountId: number
  accountName: string
  role: string
  name: string
  active: boolean
  accountCancelled: boolean
  daysUntilDeletion: number | null
  canReactivate: boolean
  createdAt: string
}
