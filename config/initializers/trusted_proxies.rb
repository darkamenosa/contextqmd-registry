# frozen_string_literal: true

require Rails.root.join("lib/trusted_proxy_ranges")

Rails.application.config.action_dispatch.trusted_proxies = TrustedProxyRanges.all
