# CLAUDE.md

Guidance for Claude Code when working with this Rails + InertiaJS React/TypeScript codebase.

## Core Rules

- Always include a confidence interval for how confident you are that the proposed solution is optimal
- DO NOT run `git add` or `git commit` without my approval
- DO NOT over-engineer. Simple solutions > complex abstractions
- Be critical — challenge suggestions that lead to poor code quality or architecture
- Before implementing, ask clarifying questions about assumptions
- Consult context7 skill for related topics before coding. If unavailable, do web research. Don't add anything you don't know
- Read `docs/tailwind.md` before writing frontend code. Read `docs/STYLE.md` before writing Ruby
- Read `docs/auth-tenant-guide.md` before adding models, controllers, or features that involve tenant data, authentication, or authorization. It covers the Identity/User/Account pattern, scoping rules, and has a safety checklist
- Read `docs/analytics.md` before modifying analytics tracking, the dashboard, visit/event models, or the Ahoy store. It covers the dedicated database, query pipeline, client-side tracker, live view, and how to extend safely
- Self-critique your work when finishing a task
- Simplicity criterion: All else being equal, simpler is better. A small improvement that adds ugly complexity is not worth it. Conversely, removing something and getting equal or better results is a great outcome — that's a simplification win. When evaluating whether to keep a change, weigh the complexity cost against the improvement magnitude. A improvement that adds 20 lines of hacky code? Probably not worth it. A improvement from deleting code? Definitely keep. An improvement of ~0 but much simpler code? Keep.
- **DO NOT GUESS** — If you can't test or verify something after 2 attempts, ask for help with specific instructions

## Development Workflow

### Before Coding
- Research: Check existing patterns first, then docs
- Questions: Clarify before implementing assumptions

### Backend
- Follow DHH/Rails conventions strictly (see patterns below)
- Use `params.expect` (Rails 8+), not `params.require().permit()`
- Inertia props: use **snake_case** in Ruby — `prop_transformer` auto-converts to camelCase
- Never run migrations automatically — ask first
- Always use gem's official generators — never manually write files that generators create
- Run `bin/rubocop --autocorrect` after changes

### Frontend
- Follow Next.js naming: files in `kebab-case.tsx`, components in `PascalCase`, props in `camelCase`
- Never modify `app/frontend/components/ui/` (shadcn managed)
- Run `npm run check && npm run lint && npm run format:check` after changes — Prettier failures are common

### Strong Parameters

```ruby
# Rails 8+ style
def item_params
  params.expect(item: [:name, :email, :phone, tags: []])
end

# Nested attributes use double brackets [[ ]]
def parent_params
  params.expect(parent: [:name, children_attributes: [[:id, :value, :_destroy]]])
end
```

Frontend must wrap form data:
```tsx
const { data, post, transform } = useForm({ name: "", email: "" })
transform((data) => ({ item: data }))
```

### Inertia Props Convention

```ruby
# Controller (snake_case) — auto-transforms to camelCase for JS
render inertia: "items/show", props: {
  item: item_props(item),
  related_items: related.map { |i| item_props(i) },
  total_count: items.count
}
```

```tsx
// Frontend receives camelCase
interface Props {
  item: Item
  relatedItems: Item[]    // from related_items
  totalCount: number      // from total_count
}
```

## Rails Patterns

### REST Actions Only (DHH Philosophy)

Only use the 7 REST actions: `index`, `show`, `new`, `edit`, `create`, `update`, `destroy`. When you need a custom action, make a new controller.

```ruby
# WRONG — custom actions
class ItemsController
  def archive; end
  def publish; end
end

# CORRECT — separate controllers with REST actions
class Items::ArchivesController
  def create; end      # POST /items/:item_id/archives
  def destroy; end     # DELETE (unarchive)
end

class Items::PublicationsController
  def create; end      # POST /items/:item_id/publications
end
```

Think in REST nouns, not verbs. Controller proliferation is good.

### Rich Domain Models Over Service Objects

```ruby
# CORRECT — rich model
@item.archive
@item.compute_score

# WRONG — unnecessary service layer
ItemArchiveService.new(@item).call
```

Extract objects only when complexity demands it. Use concerns for shared model behavior.

## Project Structure

```
app/frontend/
├── components/
│   └── ui/              # shadcn/ui (NEVER MODIFY)
├── entrypoints/         # Vite entry points
├── lib/utils.ts         # Utility functions
├── pages/               # Inertia pages matching routes
├── routes/              # Generated JS route helpers (js-routes gem)
├── ssr/                 # SSR configuration
└── types/index.ts       # Shared TypeScript types
```

## Commands

```bash
# Development
bin/setup              # Initial setup
bin/dev                # Rails (port 3000) + Vite + Solid Queue
bin/rails routes       # Show routes
bin/rails js:routes:all # Regenerate JS route helpers

# Database
bin/rails db:create    # Create all DBs (main, cache, queue, cable)
bin/rails db:migrate   # Run migrations

# Code Quality
bin/rubocop --autocorrect  # Ruby linting
npm run check              # TypeScript type check
npm run lint               # ESLint
npm run format:check       # Prettier check
bin/ci                     # Full CI pipeline

# Testing
bin/rails test             # Run all tests
bin/rails test test/models # Specific directory

# Deployment
kamal deploy           # Deploy to production
kamal app logs         # View logs
```

## Architecture

- **Backend**: Rails 8 + PostgreSQL + Solid Cache/Queue/Cable
- **Frontend**: React + TypeScript + Inertia.js + ShadcnUI + Tailwind CSS 4
- **Build**: Vite with SSR support
- **Deployment**: 3 Docker containers (web, vite SSR, job) via Kamal

### Request Flow
1. Browser → Rails router → Controller
2. Controller renders: `render inertia: "page/component", props: { ... }`
3. Inertia loads React component from `app/frontend/pages/`
4. Subsequent navigation handled client-side by Inertia router

### Frontend Routing
- Rails routes in `config/routes.rb`
- JS helpers auto-generated via `js-routes` gem to `app/frontend/routes/`
- Usage: `import { itemPath } from '@/routes'`
- Navigation: `<Link href={itemPath(item.id)}>View</Link>`

## What NOT to Do
- Run `rails server` or `bin/dev` (user manages their own server)
- Modify Rails credentials without approval
- Create custom controller actions (make a new controller)
- Store secrets in code
- Skip linting before finishing
