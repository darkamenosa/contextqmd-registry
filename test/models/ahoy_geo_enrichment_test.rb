# frozen_string_literal: true

require "test_helper"

class AhoyGeoEnrichmentTest < ActiveSupport::TestCase
  setup do
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
  end

  test "track_visit enriches visits from the bundled maxmind database" do
    assert_predicate MaxmindGeo, :available?

    request = ActionDispatch::Request.new(
      "rack.url_scheme" => "http",
      "REQUEST_METHOD" => "POST",
      "HTTP_HOST" => "localhost",
      "REMOTE_ADDR" => "10.0.0.1",
      "HTTP_CF_CONNECTING_IP" => "128.101.101.101",
      "HTTP_CF_IPCOUNTRY" => "US",
      "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
      "PATH_INFO" => "/ahoy/visits"
    )

    assert_difference -> { Ahoy::Visit.count }, 1 do
      Current.set(request: request) do
        Ahoy::Tracker.new(request: request).track_visit
      end
    end

    visit = Ahoy::Visit.order(:id).last
    assert_not_nil visit
    assert_equal "US", visit.country
    assert_equal "Minnesota", visit.region
    assert_equal "Minneapolis", visit.city
    assert_equal 44.9696, visit.latitude
    assert_equal(-93.2348, visit.longitude)
  ensure
    Current.reset
  end
end
