# Authentication & Tenant Architecture Guide

This document describes the auth and tenant model currently implemented in this repo. It is the source of truth for how `Identity`, `User`, and `Account` work together, how request scoping is established, and how to add new tenant-aware features safely.

## Core Model

### Three models, three jobs

```text
Identity = global login record
Account  = tenant / billing boundary
User     = membership connecting Identity -> Account
```

```text
Alice (Identity: alice@example.com)
|- User: "Alice" in "Alice's Account" (role: owner)
\- User: "Alice" in "Bob's Agency" (role: member)

System
|- User: "System" in "Alice's Account" (role: system)
\- User: "System" in "Bob's Agency" (role: system)
```

### Which current object to use

| Need | Use | Why |
|---|---|---|
| Sign-in state, email, OAuth, staff access | `Current.identity` | `Identity` is the global auth record |
| Per-account name and role | `Current.user` | `User` is the membership for the current account |
| Tenant scoping | `Current.account` | Business data belongs to an account |
| Admin pages outside tenant scope | `Current.identity` | `Current.user` is intentionally `nil` outside account scope |

### Two authorization dimensions

| Dimension | Stored on | Values | Used for |
|---|---|---|---|
| System role | `Identity#staff?` | `true` / `false` | `/admin/*`, Mission Control |
| Account role | `User#role` | `owner`, `admin`, `member`, `system` | Tenant-level permissions |

These are independent. A staff identity can have no account memberships and still access `/admin`. An account owner cannot access `/admin` unless their identity also has `staff: true`.

### User roles

`User.role` is a string enum with explicit, stable values:

```ruby
User.roles
# => { "owner" => "owner", "admin" => "admin", "member" => "member", "system" => "system" }
```

Role behavior:

- `owner` is the highest tenant role.
- `admin?` returns `true` for both `admin` and `owner`.
- `system` users have no identity and are excluded from the active membership scope.
- `User.active` means `active: true` and role in `owner/admin/member`.
- `User.by_role_priority` orders by `owner > admin > member > system`.

Role permission helpers on `User::Role`:

- `can_change?(other)` — true when admin and the other is not an owner, or when acting on self.
- `can_administer?(other)` — true when admin and the other is not an owner and is not self.

## Data Model

### `identities`

Global authentication records managed by Devise.

- `email`
- `encrypted_password`
- `provider`, `uid`
- `password_set_by_user`
- `staff`
- `suspended_at`
- Devise trackable and recoverable fields

Important behavior:

- `active_for_authentication?` rejects suspended identities.
- `has_many :users, dependent: :nullify`
- `has_many :accounts, through: :users`
- `has_many :access_tokens, dependent: :destroy`
- `pg_search_scope :search` indexes email plus associated user names for admin customer search (prefix matching enabled).

Identity scopes for admin:

- `Identity.active` — not suspended.
- `Identity.suspended` — suspended.
- `Identity.admin_cancelled` — active identities with at least one cancelled membership and no accessible memberships.
- `Identity.admin_active` — all other active identities (including active identities with accessible memberships and active identities with no memberships).

Identity membership helpers:

- `accessible_memberships` — active memberships excluding cancelled accounts.
- `cancelled_memberships` — active memberships belonging to cancelled accounts.
- `account_status` — returns `"active"`, `"cancelled"`, or `"inactive"` based on memberships.
- `admin_status` — convenience helper that collapses suspended and cancelled-only membership state into a single string.

### `accounts`

Tenant boundary and billing entity.

- `name`
- `personal`
- `external_account_id`

`external_account_id` is the public identifier used in `/app/:account_id/*` URLs. `Account#slug` returns `/app/#{AccountSlug.encode(external_account_id)}`.

`Account.orphaned` scope finds accounts with no non-null identity memberships remaining.

### `users`

Membership rows connecting an identity to an account.

- `identity_id` is optional
- `account_id` is required
- `name`
- `role`
- `active`

Important constraints:

- one `owner` membership per account
- one `system` user per account
- one `identity_id/account_id` membership pair when `identity_id` is present
- database check constraint: system users cannot have an identity
- `belongs_to :identity, optional: true`

`User#deactivate` sets `active: false` and clears `identity_id`. `User#reactivate` sets `active: true`.

`User::Named` provides `first_name`, `last_name`, `initials`, `familiar_name`, and an `alphabetically` scope.

### `account_cancellations`

Soft-delete records for accounts.

- `account_id` is unique
- `initiated_by_id` points to a `User`
- `initiated_by_id` is nullable so cancelled accounts survive if the initiating identity is later removed

### `access_tokens`

Personal access tokens for API authentication.

- belong to `Identity`, not `Account`
- store `token_digest`, never the raw token
- support `read` and `write` permissions (string enum)
- track `token_prefix`, `last_used_at`, and optional `expires_at`
- `AccessToken.active` scope filters by non-expired tokens

## Account Provisioning

New accounts are created through `Account.create_with_user(identity:, name:)`.

That method creates (in a transaction):

1. an account named `"#{first_name}'s Account"`
2. a system user with role `system`
3. an owner membership for the signing-in identity

```ruby
account = Account.create!(name: "#{first_name}'s Account", personal: true)
account.users.create!(name: "System", role: :system)
user = account.users.create!(identity: identity, name: name, role: :owner)
```

Sign-up and first-time Google OAuth both use this path. Returns `[user, account]`.

## Request Lifecycle

### 1. URL scope establishes `Current.account`

`config/initializers/tenanting/account_slug.rb` installs `AccountSlug::Extractor` middleware.

- Requests under `/app/:account_id/*` are decoded through `AccountSlug.decode`
- The middleware looks up `Account.find_by(external_account_id:)` and wraps in `Current.with_account(account)`
- The raw decoded ID is stored in `env["contextqmd_registry.account_id"]` for use by authorization
- Requests outside `/app/:account_id/*` run inside `Current.without_account`

Today `AccountSlug.encode` and `decode` are plain string/integer conversions. Only `external_account_id` is exposed in URLs.

### 2. Authentication establishes `Current.identity`

`Authentication` does two things:

- session auth through Devise
- bearer auth through `AccessToken.authenticate`

```ruby
def set_current_identity
  authenticate_by_access_token || set_identity_from_session
end
```

Bearer token requests:

- read `Authorization: Bearer <token>`
- resolve the identity through `AccessToken.authenticate`
- reject suspended identities
- require the token permission to allow the HTTP verb
- touch `last_used_at` on successful authentication

`read` tokens allow `GET` and `HEAD`. `write` tokens allow all verbs.

### 3. `Current.identity=` resolves `Current.user`

`Current.user` is derived inside `Current.identity=` when both an identity and an account are present.

```ruby
def identity=(identity)
  super
  if identity.present? && account.present?
    self.user = identity.users.active.find_by(account: account)
  else
    self.user = nil
  end
end
```

In the request lifecycle, this works because tenant middleware sets `Current.account` before authentication sets `Current.identity`.

```ruby
Current.with_account(account) do
  Current.identity = identity
end
```

Important implementation detail:

- `Current.with_account` and `Current.without_account` do not recompute `Current.user` on their own.
- If code changes account scope after identity has already been assigned, it must resolve memberships explicitly or reassign `Current.identity`.

For normal request flow:

- tenant routes get `Current.user`
- `/app` menu pages do not
- `/admin/*` pages do not
- public pages do not

If you are outside tenant scope, use `Current.identity` and query memberships directly.

### 4. Authorization verifies tenant access

`Authorization` runs two before_actions when both `env["contextqmd_registry.account_id"]` is present and the identity is authenticated:

1. `ensure_valid_account_scope` — returns 404 if `Current.account` is nil (invalid account ID in URL).
2. `ensure_can_access_account` — verifies `Current.account.active?` and `Current.user.active?`.

When tenant access fails:

- JSON/bearer requests return `403` JSON error
- HTML requests redirect to `app_path`
- other formats return `head :forbidden`

## Controller DSL

`ApplicationController` includes `Authentication`, `Authorization`, `ErrorHandling`, `CurrentRequest`, `CurrentTimezone`, `SetPlatform`, `RoutingHeaders`, and `RequestForgeryProtection`.

### Authentication DSL

- `allow_unauthenticated_access`
  Skips `authenticate_identity!`, `require_active_identity`, **and** `ensure_can_access_account` (chains to `allow_unauthorized_access`).

### Authorization DSL

- `allow_unauthorized_access`
  Skips `ensure_can_access_account`.
- `require_access_without_a_user`
  Skips account authorization and redirects away if `Current.user` already exists. This is available for onboarding-style flows, but is not currently used in the app.
- `disallow_account_scope`
  Skips account authorization and rejects requests that arrive with `Current.account` set (renders 404).

### Guard helpers

- `ensure_admin`
  Requires `Current.user.admin?`. Renders 403 on failure.
- `ensure_staff`
  Requires `Current.identity.staff?`. Renders 403 on failure.

## Controller Matrix

| Surface | Auth | Tenant scope | Notes |
|---|---|---|---|
| `App::BaseController` | required | required | server-side redirects auto-fill `account_id` via `default_url_options` |
| `App::MenusController` | required | disallowed | account picker at `/app` |
| `App::AccountReactivationsController` | required | disallowed | reactivate cancelled account from menu |
| `App::AccessTokensController` | required | both scoped and unscoped | works at `/app/access_tokens` and `/app/:account_id/access_tokens` |
| `Admin::BaseController` | required | disallowed | also requires `staff`, includes `Pagy::Method` |
| `PagesController` | public | disallowed | marketing pages |
| `ErrorsController` | public | disallowed | public error pages |
| Devise controllers | controller-specific | unscoped | custom Inertia auth pages |

## Route Map

| Path | Purpose | Guard |
|---|---|---|
| `/login` | sign in | public Devise controller |
| `/register` | sign up | public Devise controller |
| `/password/*` | password reset | public Devise controller |
| `/app` | account picker / default landing after app sign-in | authenticated identity |
| `/app/access_tokens` | personal access tokens (unscoped) | authenticated identity |
| `/app/account_reactivation` | reactivate cancelled account | authenticated identity, owner |
| `/app/:account_id` | redirects to dashboard | authenticated active membership |
| `/app/:account_id/dashboard` | tenant dashboard | authenticated active membership for that account |
| `/app/:account_id/settings` | profile, password, leave/cancel account | authenticated active membership for that account |
| `/app/:account_id/billing` | billing | authenticated admin or owner for that account |
| `/app/:account_id/access_tokens` | personal access tokens (scoped) | authenticated active membership for that account |
| `/admin` | redirects to `/admin/dashboard` | staff identity |
| `/admin/dashboard` | admin dashboard | staff identity |
| `/admin/customers` | identity-level customer admin | staff identity |
| `/admin/customers/:id` | customer detail | staff identity |
| `/admin/customers/:customer_id/suspension` | suspend or unsuspend a customer identity | staff identity |
| `/admin/customers/:customer_id/staff_access` | grant or revoke staff access | staff identity |
| `/admin/customers/:customer_id/account_reactivation` | reactivate a cancelled account from the selected membership | staff identity |
| `/admin/customers/bulk_suspension` | bulk suspend or unsuspend customers | staff identity |
| `/admin/jobs` | Mission Control Jobs | staff identity |
| `/` and marketing pages | public site | public |

## Inertia Shared Props

`InertiaController` shares three global props.

### `current_user`

Only present on tenant-scoped pages.

```ruby
{
  id: Current.user.id,
  name: Current.user.name,
  email: Current.user.email,
  role: Current.user.role,
  staff: Current.identity&.staff? || false,
  account_id: Current.account.external_account_id,
  account_name: Current.account.name
}
```

### `current_identity`

Present anywhere an identity is authenticated.

```ruby
{
  id: Current.identity.id,
  name: Current.identity.display_name,
  email: Current.identity.email,
  staff: Current.identity.staff?,
  default_account_id: ...,
  default_account_name: ...,
  default_account_role: ...
}
```

`default_account_id`, `default_account_name`, and `default_account_role` come from the first accessible (non-cancelled) membership, selected by role priority (`owner > admin > member`) then `created_at` ascending.

### `request_context`

Shared on all Inertia responses:

- `request_id`
- `timezone`
- `platform`

`CurrentRequest` also records `http_method`, `user_agent`, `ip_address`, and `referrer` for downstream use.

## Auth Entry Points

### Email/password sign-in

`Identities::SessionsController` renders the login page with Inertia and redirects after sign-in like this:

1. allowed stored location, if present
2. `app_path` if the identity has active or cancelled memberships
3. `admin_dashboard_path` if the identity is staff
4. `root_path` otherwise

Stored location validation:

- `/admin/*` locations are only reused for staff identities
- `/app/access_tokens` is always allowed
- `/app` and `/app/*` locations are only reused when the identity has accessible memberships
- all other stored locations are rejected

Rate limited: 10 requests per 3 minutes on `create`.

### Registration

`Identities::RegistrationsController#create`:

- builds the identity from sign-up params
- derives user name from `params[:user][:name]` or email prefix
- wraps in a transaction: save identity, mark password set, provision account
- rescues `RecordInvalid` and `RecordNotUnique` with error redirects
- obfuscates duplicate email errors for security
- redirects to `app_path`

Rate limited: 10 requests per 3 minutes on `create`.

### Password reset

`Identities::PasswordsController`:

- renders reset request and reset form pages with Inertia
- sends reset instructions through Devise
- stores reset token in session to survive page reloads
- marks `password_set_by_user` after a successful password reset
- signs the identity in and redirects via `after_authentication_path_for`
- redirects suspended identities to sign-in with the inactive message

Rate limited: 5 requests per 3 minutes on `create`.

### Google OAuth

`Identities::OmniauthCallbacksController#google_oauth2`:

- finds an identity by `provider/uid` first
- falls back to existing identity by email
- backfills `provider` and `uid` onto an existing email/password identity
- raises `GoogleOauthEmailError` if the identity is already linked to a different OAuth provider
- creates a new identity if needed
- provisions an account if the identity was just created
- retries once on `RecordNotUnique` (race condition guard)
- validates Google email is verified and authoritative (`@gmail.com`, `@googlemail.com`, or Google Workspace domain)

Suspended identities still fail sign-in after OAuth resolution.

### Personal access tokens

Token management works at both scoped and unscoped paths:

- `/app/:account_id/access_tokens` — tenant-scoped view
- `/app/access_tokens` — unscoped view (outside tenant context)

Both routes use `App::AccessTokensController`, which queries `Current.identity.access_tokens` (not account-scoped). Redirects after create/destroy use the appropriate path based on whether `Current.account` is present.

Key behavior:

- raw token is shown once at creation time (via flash)
- only the SHA-256 digest is persisted
- revoking a token deletes the row
- bearer auth still depends on URL account scope for tenant authorization

That last point matters: an access token does not bypass tenant checks. On `/app/:account_id/*`, the request still has to resolve an active membership for that account.

## Account Selection

`GET /app` is the unscoped account picker.

`App::MenusController#show`:

- loads accessible (non-cancelled) memberships for `Current.identity`
- loads cancelled memberships separately (with cancellation data)
- redirects straight to the dashboard when exactly one accessible membership and no cancelled memberships
- renders the menu when there are multiple accessible memberships or cancelled memberships exist
- redirects to `root_path` with an alert when there are no memberships at all

The menu page shows cancelled accounts with days remaining until incineration, allowing owners to reactivate.

`/app/:account_id` itself redirects to `/app/:account_id/dashboard`.

## Account Reactivation

Two paths for reactivating cancelled accounts:

### User-facing: `App::AccountReactivationsController`

- Route: `POST /app/account_reactivation`
- Requires authenticated identity (disallows account scope)
- Finds the membership by `params[:membership_id]` from the identity's active users
- Validates the user is an owner and the account is cancelled
- Calls `account.reactivate`
- Redirects to the account dashboard

### Admin-facing: `Admin::Customers::AccountReactivationsController`

- Route: `POST /admin/customers/:customer_id/account_reactivation`
- Requires staff identity
- Finds the selected membership for the customer identity from `params[:membership_id]`
- Validates the account is cancelled
- Calls `account.reactivate`
- Redirects to the customer detail page

## Account Lifecycle

### Active vs cancelled

`Account#active?` is just `!cancelled?`.

Cancellation is modeled as a separate `Account::Cancellation` row, not a boolean column.

```ruby
account.cancel(initiated_by: Current.user)
account.cancelled?
account.reactivate
```

`Account::Cancellable` uses callbacks for both `cancel` and `reactivate`. Both methods use `with_lock` for thread safety.

### Incineration

`Account::Incineratable` defines:

- `INCINERATION_GRACE_PERIOD = 30.days`
- `Account.due_for_incineration`
- `Account#incinerate`

`Account` class methods for bulk incineration:

- `Account.incinerate_due_now` — processes scheduled incinerations (cancelled beyond grace period).
- `Account.incinerate_orphaned_now(account_ids)` — immediately incinerates orphaned accounts from a given set.
- `Account.incinerate_orphaned_later(account_ids)` — enqueues `AccountIncinerationJob` for async orphan cleanup.
- `Account.incinerate_accounts(scope)` — iterates a scope, logs failures, returns failed IDs.

`AccountIncinerationJob` has dual-mode:

- With `orphaned_account_ids:` keyword — incinerates specific orphaned accounts (triggered by identity destruction).
- Without arguments — runs scheduled incineration of accounts past grace period.

The job retries on `StandardError` (wait 5 minutes, up to 10 attempts) and re-raises if any accounts fail to incinerate.

Scheduled in `config/recurring.yml` for production at 3:00 AM daily.

### Leaving an account

`App::SettingsController#destroy` has two paths:

- owners cancel the whole account
- non-owners deactivate their own membership and leave the account

After either action, if the identity still has accessible memberships, redirects to `app_path`. Otherwise, signs the identity out and redirects to `root_path`.

### Identity cleanup

Two identity flows can remove memberships and accounts:

#### `Identity#deactivate_customer_access`

Used by admin customer management.

It (inside a lock):

- loads all memberships with accounts
- deactivates all memberships (clears `identity_id`, sets `active: false`)
- suspends the identity and revokes staff access
- incinerates accounts that become orphaned

Shared accounts with other remaining identities survive.

#### `Identity#destroy`

Before destroy (`prepare_account_cleanup`):

- capture affected account ids
- reassign `Account::Cancellation#initiated_by` to the account's system user if the destroyed membership initiated cancellation
- deactivate all users (clears `identity_id`)

After destroy commit (`destroy_orphaned_accounts`):

- enqueue `AccountIncinerationJob` with orphaned account ids for async cleanup

This is why `initiated_by_id` is nullable and why every account has a system user.

## Admin Surface

System admin is identity-centric, not membership-centric.

### `/admin/customers`

`Admin::CustomersController` works on `Identity` records, not tenant `User` rows.

Features:

- full-text search across email and user names (prefix matching)
- filter by `active`, `cancelled`, or `suspended` with counts for each status
- sort by `email` or `created_at`
- paginated with Pagy (25 per page)
- index view shows identity-level props (`email`, `name`, `auth_method`, `staff`, `status`, `accounts_count`)
- customer `status` in both index and show is `Identity#status` (login/suspension state), not cancelled-account state
- cancelled-account state is surfaced separately through the `cancelled` filter and membership props like `account_cancelled`, `days_until_deletion`, and `can_reactivate`
- show view includes all memberships with account details, cancellation status, and days until deletion

Nested REST controllers handle customer actions:

- `Admin::Customers::SuspensionsController` — suspend/unsuspend
- `Admin::Customers::StaffAccessesController` — grant/revoke staff access
- `Admin::Customers::BulkSuspensionsController` — bulk suspend/unsuspend (self-excluded)
- `Admin::Customers::AccountReactivationsController` — reactivate cancelled accounts

Self-protection rules:

- you cannot suspend yourself
- you cannot revoke your own staff access
- bulk operations exclude your own identity

### `/admin/jobs`

Mission Control Jobs is mounted at `/admin/jobs` behind both:

- route-level staff authentication (`authenticate :identity` constraint)
- `Admin::BaseController#ensure_staff`

## Error Handling

`ErrorHandling` concern provides centralized error responses:

- `StandardError` — 500 (production only; re-raises in dev)
- `RoutingError`, `RecordNotFound` — 404
- `InvalidAuthenticityToken` — 419 (Session Expired)
- `UnknownFormat` — 406

Error responses adapt to request type:

- JSON/bearer requests get JSON error responses
- HTML requests render Inertia error components (path-aware: `admin/errors/show`, `app/errors/show`, or `errors/show`)
- Other formats get `head :status`

`ErrorsController` provides public error pages at `/errors/:status` with a fixed set of error payloads (401, 403, 404, 406, 419, 422, 500, 503).

## Adding Tenant Data Safely

Every tenant-owned business model should follow this pattern.

### 1. Add `account_id` in the migration

```ruby
class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.references :account, null: false, foreign_key: true
      t.references :creator, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.timestamps
    end
  end
end
```

### 2. Model the tenant relationship explicitly

Prefer deriving the account from a parent relationship instead of reading `Current.account` directly when you can.

```ruby
class Project < ApplicationRecord
  belongs_to :account, default: -> { creator.account }
  belongs_to :creator, class_name: "User", default: -> { Current.user }

  validates :name, presence: true
end
```

### 3. Wire the account association

```ruby
class Account < ApplicationRecord
  has_many :projects, dependent: :destroy
end
```

### 4. Scope controllers through `Current.account`

```ruby
class App::ProjectsController < App::BaseController
  def index
    projects = Current.account.projects.order(created_at: :desc)

    render inertia: "app/projects/index", props: {
      projects: projects.map { |project| project_props(project) }
    }
  end

  def show
    project = Current.account.projects.find(params[:id])

    render inertia: "app/projects/show", props: {
      project: project_props(project)
    }
  end
end
```

### 5. Put the routes under account scope

```ruby
scope "app/:account_id", constraints: { account_id: /\d+/ } do
  namespace :app, path: "" do
    resources :projects
  end
end
```

Use `App::BaseController` for tenant pages so server-side redirects automatically include the current `account_id`.

## Background Jobs

`config/initializers/tenanting/active_job_tenant.rb` prepends `TenantAwareJob` onto `ActiveJob::Base`.

Behavior:

- capture `Current.account` when the job is initialized
- serialize the account as a GlobalID
- restore `Current.account` around `perform_now`
- `enqueue_after_transaction_commit = true` ensures jobs enqueue after the wrapping transaction commits

For cross-account work, still pass explicit models or ids and switch account context deliberately.

## Request Forgery Protection for API Calls

`RequestForgeryProtection` uses:

```ruby
protect_from_forgery with: :exception
```

Bearer-token JSON requests bypass CSRF verification:

```ruby
def verified_request?
  super || bearer_token_json_request?
end

def bearer_token_json_request?
  request.format.json? && request.authorization.to_s.start_with?("Bearer")
end
```

CSRF is bypassed only when both conditions are true:

- `request.format.json?`
- `Authorization` header starts with `"Bearer"`

This makes non-browser bearer-token clients work without a CSRF token while still protecting all browser requests (including JSON requests made by browsers, which won't have a Bearer header).

## Error Context

All reported errors include:

- `identity_id`
- `account_id` as the external account id

This is wired through `config/initializers/error_context.rb` using `Rails.error.add_middleware`.

## Optional: Active Storage Tenanting

If Active Storage is installed, `config/initializers/tenanting/active_storage_tenant.rb` injects `belongs_to :account` into framework models:

- `ActiveStorage::Attachment` — defaults account from `record.account`
- `ActiveStorage::Blob` — defaults account from `Current.account`
- `ActiveStorage::VariantRecord` — defaults account from `blob.account`

Purpose:

- every file is owned by an account
- file rows are destroyed when an account is incinerated

If you enable Active Storage, add `account_id` to the framework tables before relying on this initializer.

## Anti-Patterns

### Never query tenant data without account scope

```ruby
# Wrong
Project.all
Project.find(params[:id])

# Correct
Current.account.projects
Current.account.projects.find(params[:id])
```

### Never use `Current.user` outside tenant scope

`Current.user` is `nil` on:

- `/admin/*`
- `/app`
- public pages

Use `Current.identity` and query memberships directly when you are unscoped.

### Never mix system and account roles

```ruby
# Wrong for tenant features
Current.identity.staff?

# Correct for tenant features
Current.user.admin?
```

`staff` is for system admin. `User#role` is for tenant authorization.

### Never attach an identity to a system user

System users exist so automation and account cleanup have an actor even when no human membership remains.

### Never assume access tokens bypass tenant authorization

Bearer tokens prove identity. They do not replace `Current.account` or `Current.user`.

## Safety Checklist

- [ ] Tenant models include `account_id`
- [ ] Tenant migrations add `t.references :account, null: false, foreign_key: true`
- [ ] `Account` owns the new association with `dependent: :destroy` where appropriate
- [ ] Controllers query through `Current.account`
- [ ] Nested queries stay scoped through tenant-owned parents
- [ ] Tenant pages live under `/app/:account_id/*`
- [ ] Unscoped pages that must reject tenant context call `disallow_account_scope`
- [ ] Tenant authorization uses `Current.user.admin?` or `Current.user.owner?`
- [ ] System admin authorization uses `Current.identity.staff?`
- [ ] URLs and redirects use `external_account_id`, not `accounts.id`
- [ ] Background jobs preserve or explicitly set tenant context
- [ ] API endpoints decide whether they are session-auth, bearer-auth, or both
- [ ] If Active Storage is involved, framework tables also carry `account_id`
