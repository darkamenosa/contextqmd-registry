# frozen_string_literal: true

class Analytics::GoogleSearchConsole::Configuration
  class << self
    def client_id
      ::Analytics::Configuration.google_search_console.client_id.presence
    end

    def client_secret
      ::Analytics::Configuration.google_search_console.client_secret.presence
    end

    def configured?
      client_id.present? && client_secret.present?
    end
  end
end
