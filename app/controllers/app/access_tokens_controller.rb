# frozen_string_literal: true

module App
  class AccessTokensController < InertiaController
    include Pagy::Method
    include BlockSearchEngineIndexing

    def index
      scope = Current.identity.access_tokens.order(created_at: :desc)
      pagy, tokens = pagy(:offset, scope, limit: 10)

      render inertia: "app/access-tokens/index", props: {
        access_tokens: tokens.map { |t| token_props(t) },
        pagination: pagination_props(pagy),
        new_token: flash[:new_token]
      }
    end

    def create
      _access_token, raw_token = AccessToken.generate(
        identity: Current.identity,
        name: token_params[:name],
        permission: token_params[:permission]
      )

      redirect_to access_tokens_path_for_current_scope,
        flash: { new_token: raw_token },
        notice: "Token created."
    end

    def destroy
      token = Current.identity.access_tokens.find(params[:id])
      token.revoke

      redirect_to access_tokens_path_for_current_scope, notice: "Token revoked."
    end

    private

      def access_tokens_path_for_current_scope
        if Current.account.present?
          scoped_app_access_tokens_path(account_id: Current.account.external_account_id)
        else
          app_access_tokens_path
        end
      end

      def token_params
        params.expect(access_token: [ :name, :permission ])
      end

      def token_props(token)
        {
          id: token.id,
          name: token.name,
          permission: token.permission,
          token_prefix: token.token_prefix,
          created_at: token.created_at.iso8601,
          last_used_at: token.last_used_at&.iso8601
        }
      end
  end
end
