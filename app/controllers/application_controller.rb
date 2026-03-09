# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Authentication
  include Authorization
  include ErrorHandling
  include CurrentRequest
  include CurrentTimezone
  include SetPlatform
  include RoutingHeaders
  include RequestForgeryProtection

  etag { "v1" }
  allow_browser versions: :modern
end
