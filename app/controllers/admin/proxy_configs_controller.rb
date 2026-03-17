# frozen_string_literal: true

module Admin
  class ProxyConfigsController < BaseController
    def index
      base = if params[:query].present?
        CrawlProxyConfig.where(
          "name ILIKE :q OR host ILIKE :q OR provider ILIKE :q",
          q: "%#{params[:query]}%"
        )
      else
        CrawlProxyConfig.all
      end

      scope = apply_tab_filter(base)

      pagy, configs = pagy(:offset,
        scope.order(sort_column => sort_direction),
        limit: 25
      )

      render inertia: "admin/proxy-configs/index", props: {
        proxy_configs: configs.map { |c| config_row_props(c) },
        pagination: pagination_props(pagy),
        total_count: CrawlProxyConfig.count,
        active_count: CrawlProxyConfig.active.count,
        filters: {
          query: params[:query] || "",
          tab: params[:tab] || "all",
          sort: params[:sort] || "priority",
          direction: params[:direction] || "desc"
        }
      }
    end

    def show
      config = CrawlProxyConfig.find(params[:id])
      leases = config.crawl_proxy_leases.order(created_at: :desc).limit(20)

      render inertia: "admin/proxy-configs/show", props: {
        proxy_config: config_detail_props(config),
        leases: leases.map { |l| lease_props(l) }
      }
    end

    def new
      render inertia: "admin/proxy-configs/new", props: {
        schemes: CrawlProxyConfig::SCHEMES,
        kinds: CrawlProxyConfig::KINDS,
        scopes: CrawlProxyConfig::SCOPES
      }
    end

    def create
      config = CrawlProxyConfig.new(config_params)

      if config.save
        redirect_to admin_proxy_config_path(config), notice: "Proxy created."
      else
        redirect_to new_admin_proxy_config_path,
                    alert: config.errors.full_messages.join(", ")
      end
    end

    def edit
      config = CrawlProxyConfig.find(params[:id])

      render inertia: "admin/proxy-configs/edit", props: {
        proxy_config: config_edit_props(config),
        schemes: CrawlProxyConfig::SCHEMES,
        kinds: CrawlProxyConfig::KINDS,
        scopes: CrawlProxyConfig::SCOPES
      }
    end

    def update
      config = CrawlProxyConfig.find(params[:id])
      filtered_params = config_params
      filtered_params.delete(:password) if filtered_params[:password].blank?

      if config.update(filtered_params)
        redirect_to admin_proxy_config_path(config), notice: "Proxy updated."
      else
        redirect_to edit_admin_proxy_config_path(config),
                    alert: config.errors.full_messages.join(", ")
      end
    end

    def destroy
      config = CrawlProxyConfig.find(params[:id])
      config.destroy!
      redirect_to admin_proxy_configs_path, notice: "Proxy \"#{config.name}\" deleted."
    end

    private

      def sort_column
        %w[name host priority consecutive_failures updated_at created_at].include?(params[:sort]) ? params[:sort] : "priority"
      end

      def sort_direction
        %w[asc desc].include?(params[:direction]) ? params[:direction] : "desc"
      end

      def apply_tab_filter(scope)
        case params[:tab]
        when "active" then scope.active
        when "inactive" then scope.where(active: false)
        when "cooling" then scope.where("cooldown_until > ?", Time.current)
        else scope
        end
      end

      def config_params
        params.expect(proxy_config: [
          :name, :scheme, :host, :port, :username, :password,
          :kind, :usage_scope, :priority, :max_concurrency,
          :lease_ttl_seconds, :active, :provider, :notes,
          :supports_sticky_sessions
        ])
      end

      def config_row_props(config)
        {
          id: config.id,
          name: config.name,
          scheme: config.scheme,
          host: config.host,
          port: config.port,
          kind: config.kind,
          usage_scope: config.usage_scope,
          priority: config.priority,
          active: config.active,
          consecutive_failures: config.consecutive_failures,
          cooldown_until: config.cooldown_until&.iso8601,
          last_success_at: config.last_success_at&.iso8601,
          last_failure_at: config.last_failure_at&.iso8601,
          active_lease_count: config.active_lease_count,
          max_concurrency: config.max_concurrency,
          provider: config.provider,
          updated_at: config.updated_at.iso8601
        }
      end

      def config_detail_props(config)
        {
          id: config.id,
          name: config.name,
          scheme: config.scheme,
          host: config.host,
          port: config.port,
          username: config.username,
          kind: config.kind,
          usage_scope: config.usage_scope,
          priority: config.priority,
          active: config.active,
          max_concurrency: config.max_concurrency,
          lease_ttl_seconds: config.lease_ttl_seconds,
          supports_sticky_sessions: config.supports_sticky_sessions,
          consecutive_failures: config.consecutive_failures,
          cooldown_until: config.cooldown_until&.iso8601,
          last_success_at: config.last_success_at&.iso8601,
          last_failure_at: config.last_failure_at&.iso8601,
          last_error_class: config.last_error_class,
          last_target_host: config.last_target_host,
          disabled_reason: config.disabled_reason,
          provider: config.provider,
          notes: config.notes,
          active_lease_count: config.active_lease_count,
          created_at: config.created_at.iso8601,
          updated_at: config.updated_at.iso8601
        }
      end

      def config_edit_props(config)
        {
          id: config.id,
          name: config.name,
          scheme: config.scheme,
          host: config.host,
          port: config.port,
          username: config.username,
          password_present: config.password.present?,
          kind: config.kind,
          usage_scope: config.usage_scope,
          priority: config.priority,
          active: config.active,
          max_concurrency: config.max_concurrency,
          lease_ttl_seconds: config.lease_ttl_seconds,
          supports_sticky_sessions: config.supports_sticky_sessions,
          provider: config.provider,
          notes: config.notes
        }
      end

      def lease_props(lease)
        {
          id: lease.id,
          session_key: lease.session_key,
          usage_scope: lease.usage_scope,
          target_host: lease.target_host,
          sticky_session: lease.sticky_session,
          active: lease.active?,
          expires_at: lease.expires_at.iso8601,
          last_seen_at: lease.last_seen_at.iso8601,
          released_at: lease.released_at&.iso8601,
          created_at: lease.created_at.iso8601
        }
      end
  end
end
