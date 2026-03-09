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

// Admin customer types
export type AdminCustomer = {
  id: number
  email: string
  name: string | null
  authMethod: string
  staff: boolean
  status: string
  accountsCount: number
  createdAt: string
}

export type AdminCustomerDetail = {
  id: number
  email: string
  name: string | null
  authMethod: string
  staff: boolean
  status: string
  suspendedAt: string | null
  createdAt: string
  memberships: AdminCustomerMembership[]
}

export type AdminCustomerMembership = {
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
