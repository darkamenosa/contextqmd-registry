# frozen_string_literal: true

module Identities
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    include InertiaFlash
    GoogleOauthEmailError = Class.new(StandardError)

    def google_oauth2
      auth = request.env["omniauth.auth"]

      identity = find_or_create_identity(auth)

      if identity.active_for_authentication?
        sign_in(:identity, identity)
        redirect_to after_authentication_path_for(identity), notice: "Signed in with Google."
      else
        redirect_to new_identity_session_path, alert: I18n.t("devise.failure.#{identity.inactive_message}")
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, GoogleOauthEmailError
      redirect_to new_identity_session_path, alert: "Google sign-in failed."
    end

    private
      def find_or_create_identity(auth)
        retries ||= 0

        Identity.transaction do
          created_identity = false
          identity = Identity.find_by(provider: auth.provider, uid: auth.uid)

          if identity.nil?
            email = authoritative_google_email(auth)
            identity = Identity.find_by(email: email)
          end

          if identity
            if oauth_linked_identity?(identity)
              raise GoogleOauthEmailError unless identity.provider == auth.provider && identity.uid == auth.uid
            else
              identity.update!(provider: auth.provider, uid: auth.uid)
            end
          else
            identity = Identity.create!(
              email: authoritative_google_email(auth),
              password: Devise.friendly_token.first(20),
              provider: auth.provider,
              uid: auth.uid
            )
            created_identity = true
          end

          if created_identity
            user_name = auth.info.name.presence || identity.email.split("@").first
            Account.create_with_user(identity: identity, name: user_name)
          end

          identity
        end
      rescue ActiveRecord::RecordNotUnique
        retries += 1
        retry if retries <= 1
        raise
      end

      def authoritative_google_email(auth)
        email = auth.info.email.to_s.strip.downcase

        if email.present? && google_email_verified?(auth) && google_email_authoritative?(email, auth)
          email
        else
          raise GoogleOauthEmailError
        end
      end

      def google_email_verified?(auth)
        truthy?(auth.info.email_verified) || truthy?(auth.extra&.raw_info&.[]("email_verified"))
      end

      def google_email_authoritative?(email, auth)
        email.end_with?("@gmail.com", "@googlemail.com") || auth.extra&.raw_info&.[]("hd").present?
      end

      def oauth_linked_identity?(identity)
        identity.provider.present? && identity.uid.present?
      end

      def truthy?(value)
        value == true || value == "true"
      end
  end
end
