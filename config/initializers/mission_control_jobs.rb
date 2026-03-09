# frozen_string_literal: true

# Keep Mission Control under the same admin guardrails as the rest of /admin.
MissionControl::Jobs.base_controller_class = "Admin::BaseController"
