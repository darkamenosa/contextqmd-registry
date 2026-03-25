# frozen_string_literal: true

module AnalyticsVisitBoundary
  extend self

  FORCE_NEW_VISIT_SESSION_KEY = "analytics.force_new_visit"

  def mark_sign_in!(session:, previous_identity_id:, next_identity_id:)
    return unless session
    return if previous_identity_id.blank? || next_identity_id.blank?
    return if previous_identity_id.to_s == next_identity_id.to_s

    session[FORCE_NEW_VISIT_SESSION_KEY] = true
  end

  def mark_sign_out!(session:, identity_id:)
    return unless session
    return if identity_id.blank?

    session[FORCE_NEW_VISIT_SESSION_KEY] = true
  end

  def force_new_visit?(request_or_session)
    session = session_for(request_or_session)
    return false unless session

    truthy?(session[FORCE_NEW_VISIT_SESSION_KEY])
  end

  def consume_force_new_visit!(request_or_session)
    session = session_for(request_or_session)
    return false unless session

    truthy?(session.delete(FORCE_NEW_VISIT_SESSION_KEY))
  end

  private
    def session_for(request_or_session)
      return request_or_session.session if request_or_session.respond_to?(:session)

      request_or_session
    end

    def truthy?(value)
      value == true || value == 1 || value == "1" || value == "true"
    end
end
