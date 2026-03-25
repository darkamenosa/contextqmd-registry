# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"
  step "Style: JavaScript", "npm run check"
  step "Style: ESLint", "npm run lint"
  step "Style: Prettier", "npm run format:check"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"

  step "Build: Vite test assets", "RAILS_ENV=test bin/vite build --clear"

  step "Tests: Node", "node --test test/frontend/*.test.mjs"
  step "Tests: Rails", "bin/rails test"
  # step "Tests: System", "bin/rails test:system"  # Rails 8.1+ no longer generates system tests by default
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"

  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
