# frozen_string_literal: true

module AccountSlug
  ID_PATTERN = /\d+/
  PATH_INFO_MATCH = %r{\A/app/(#{AccountSlug::ID_PATTERN})(?=/|$)}

  class Extractor
    def initialize(app)
      @app = app
    end

    def call(env)
      request = ActionDispatch::Request.new(env)
      env["contextqmd_registry.account_id"] = extract_account_id(request)

      if env["contextqmd_registry.account_id"]
        account = Account.find_by(external_account_id: env["contextqmd_registry.account_id"])
        Current.with_account(account) { @app.call env }
      else
        Current.without_account { @app.call env }
      end
    end

    private
      def extract_account_id(request)
        script_name_match = request.script_name.to_s.match(PATH_INFO_MATCH)
        return AccountSlug.decode(script_name_match[1]) if script_name_match

        path_info_match = request.path_info.match(PATH_INFO_MATCH)
        return AccountSlug.decode(path_info_match[1]) if path_info_match

        nil
      end
  end

  def self.decode(slug) = slug.to_i
  def self.encode(id) = id.to_s
end

Rails.application.config.middleware.insert_after Rack::TempfileReaper, AccountSlug::Extractor
