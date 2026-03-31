# frozen_string_literal: true

require "test_helper"

class AnalyticsCookielessIdentityTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers
  include TenantTestHelper

  BROWSER_HEADERS = {
    "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36",
    "REMOTE_ADDR" => "203.0.113.42"
  }.freeze

  setup do
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "cookieless event ingestion reuses the recent server-side visit without client tokens" do
    perform_analytics_jobs do
      assert_difference -> { Ahoy::Visit.count }, +1 do
        assert_difference -> { Ahoy::Event.count }, +1 do
          bootstrap_and_track_pageview(tracked_page_path, title: "About")
        end
      end
    end

    assert_response :success
    visit = Ahoy::Visit.order(:id).last

    assert_no_difference -> { Ahoy::Visit.count } do
      assert_difference -> { Ahoy::Event.count }, +1 do
        post "/a/e",
          params: {
            events: [
              {
                name: "engagement",
                properties: {
                  page: tracked_page_path,
                  url: tracked_page_url,
                  title: "About",
                  referrer: "",
                  screen_size: "1440x900"
                },
                time: Time.current.iso8601
              }
            ]
          },
          as: :json,
          headers: BROWSER_HEADERS
      end
    end

    assert_response :success
    assert_equal visit.id, Ahoy::Event.order(:id).last.visit_id
    assert_equal visit.id, Ahoy::Visit.order(:id).last.id
  end

  test "cookieless repeat events do not enqueue profile resolution again for an already resolved anonymous visit" do
    perform_analytics_jobs do
      bootstrap_and_track_pageview(tracked_page_path, title: "About")
    end

    clear_enqueued_jobs

    assert_enqueued_jobs 0, only: Analytics::ProfileResolutionJob do
      post "/a/e",
        params: {
          events: [
            {
              name: "engagement",
              properties: {
                page: tracked_page_path,
                url: tracked_page_url,
                title: "About",
                referrer: "",
                screen_size: "1440x900"
              },
              time: Time.current.iso8601
            }
          ]
        },
        as: :json,
        headers: BROWSER_HEADERS
    end

    assert_response :success
  end

  test "burst event ingest on a fresh anonymous visit coalesces profile resolution" do
    assert_difference -> { Ahoy::Visit.count }, +1 do
      assert_difference -> { Ahoy::Event.count }, +2 do
        assert_enqueued_jobs 1, only: Analytics::ProfileResolutionJob do
          post "/a/e",
            params: {
              events: [
                {
                  name: "pageview",
                  properties: {
                    page: "/about",
                    url: about_url,
                    title: "About",
                    referrer: "",
                    screen_size: "1440x900"
                  },
                  time: Time.current.iso8601
                },
                {
                  name: "engagement",
                  properties: {
                    page: "/about",
                    url: about_url,
                    title: "About",
                    referrer: "",
                    screen_size: "1440x900",
                    engaged_ms: 1200
                  },
                  time: (Time.current + 1.second).iso8601
                }
              ]
            },
            as: :json,
            headers: BROWSER_HEADERS
        end
      end
    end

    assert_response :success
  end

  test "server-side tracked page sets the analytics browser cookie" do
    get tracked_page_path, headers: BROWSER_HEADERS

    assert_response :success
    assert_includes response.headers["Set-Cookie"].to_s, Analytics::BrowserIdentity::COOKIE_NAME
  end

  test "signed-in visits persist identity name and email on the analytics profile" do
    identity, = create_tenant(
      email: "analytics-profile-#{SecureRandom.hex(4)}@example.com",
      name: "Analytics Profile User"
    )

    sign_in(identity)

    perform_analytics_jobs do
      bootstrap_and_track_pageview(tracked_page_path, title: "About")
    end

    assert_response :success

    visit = Ahoy::Visit.order(:id).last
    profile = visit.analytics_profile

    assert_not_nil profile
    assert_equal AnalyticsProfile::STATUS_IDENTIFIED, profile.status
    assert_equal "Analytics Profile User", profile.traits["display_name"]
    assert_equal identity.email, profile.traits["email"]
  end

  test "first-party pageview tracking includes authentication screens" do
    [
      [ new_identity_session_path, "/login" ],
      [ new_identity_registration_path, "/register" ],
      [ new_identity_password_path, "/password/new" ]
    ].each do |path, expected_page|
      perform_analytics_jobs do
        assert_difference -> { Ahoy::Event.count }, +1 do
          bootstrap_and_track_pageview(path, title: "Page")
        end
      end

      assert_response :success
      event = Ahoy::Event.order(:id).last
      assert_equal "pageview", event.name
      assert_equal expected_page, event.properties["page"]
    end
  end

  test "server-side tracking respects site include path rules" do
    site = Analytics::Bootstrap.ensure_default_site!(host: "localhost")
    Analytics::TrackingRules.save!(
      include_paths: [ "/blog/**" ],
      exclude_paths: [],
      site: site
    )

    perform_analytics_jobs do
      assert_no_difference -> { Ahoy::Visit.count } do
        assert_no_difference -> { Ahoy::Event.count } do
          get root_path, headers: BROWSER_HEADERS
        end
      end
    end

    assert_response :success
  end

  test "first-party pageview tracking includes authenticated app dashboard pages" do
    identity, account, = create_tenant(
      email: "analytics-dashboard-#{SecureRandom.hex(4)}@example.com",
      name: "Analytics Dashboard User"
    )

    sign_in(identity)

    perform_analytics_jobs do
      assert_difference -> { Ahoy::Visit.count }, +1 do
        assert_difference -> { Ahoy::Event.count }, +1 do
          bootstrap_and_track_pageview(app_dashboard_path(account_id: account.external_account_id), title: "Dashboard")
        end
      end
    end

    assert_response :success

    visit = Ahoy::Visit.order(:id).last
    event = Ahoy::Event.order(:id).last

    assert_equal identity.id, visit.user_id
    assert_equal "pageview", event.name
    assert_equal app_dashboard_path(account_id: account.external_account_id), event.properties["page"]
  end

  test "first-party pageview visit stores request host and drops same-site referrers" do
    perform_analytics_jobs do
      bootstrap_and_track_pageview(tracked_page_path, title: "About", headers: BROWSER_HEADERS.merge("HTTP_REFERER" => tracked_page_url))
    end

    assert_response :success

    visit = Ahoy::Visit.order(:id).last
    assert_not_nil visit
    assert_equal URI.parse(tracked_page_url).host, visit.hostname
    assert_nil visit.referrer
    assert_nil visit.referring_domain
  end

  test "first-party pageview visit stores browser and os versions from the request user agent" do
    perform_analytics_jobs do
      bootstrap_and_track_pageview(tracked_page_path, title: "About")
    end

    assert_response :success

    visit = Ahoy::Visit.order(:id).last
    assert_equal "Chrome", visit.browser
    assert_equal "146.0.0.0", visit.browser_version
    assert_equal "Mac", visit.os
    assert_equal "10.15.7", visit.os_version
    assert_equal "Desktop", visit.device_type
  end

  test "first-party pageview tracking assigns analytics site scope from the request host" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    boundary = site.boundaries.find_by!(primary: true)

    host! "docs.example.test"

    perform_analytics_jobs do
      bootstrap_and_track_pageview(tracked_page_path, title: "About")
    end

    assert_response :success

    visit = Ahoy::Visit.order(:id).last
    event = Ahoy::Event.order(:id).last

    assert_equal site.id, visit.analytics_site_id
    assert_equal boundary.id, visit.analytics_site_boundary_id
    assert_equal site.id, event.analytics_site_id
    assert_equal boundary.id, event.analytics_site_boundary_id
  end

  test "first-party pageview tracking broadcasts live updates for the resolved analytics site" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    captured_sites = []
    analytics_live_state_singleton = class << Analytics::LiveState; self; end

    host! "docs.example.test"

    analytics_live_state_singleton.alias_method :__test_original_broadcast_later, :broadcast_later
    analytics_live_state_singleton.define_method(:broadcast_later) do |site: nil, **|
      captured_sites << site
    end

    begin
      bootstrap_and_track_pageview(tracked_page_path, title: "About")
    ensure
      analytics_live_state_singleton.alias_method :broadcast_later, :__test_original_broadcast_later
      analytics_live_state_singleton.remove_method :__test_original_broadcast_later
    end

    assert_includes captured_sites, site
  ensure
    host! "www.example.com"
  end

  test "public event ingest respects site exclude path rules" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    token = Analytics::TrackerSiteToken.generate(site: site, mode: "external", expires_in: 180.days)
    Analytics::TrackingRules.save!(
      include_paths: [],
      exclude_paths: [ "/private/**" ],
      site: site
    )

    assert_no_difference -> { Ahoy::Event.count } do
      post "/a/e",
        params: {
          events: [
            {
              name: "pageview",
              site_token: token,
              properties: {
                page: "/private/plan",
                url: "https://docs.example.test/private/plan",
                title: "Private",
                referrer: "",
                screen_size: "1440x900"
              },
              time: Time.current.iso8601
            }
          ]
        },
        as: :json,
        headers: BROWSER_HEADERS
    end

    assert_response :success
  end

  test "public event ingest broadcasts live updates for the resolved analytics site" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    token = Analytics::TrackerSiteToken.generate(site: site, mode: "external", expires_in: 180.days)
    captured_sites = []
    analytics_live_state_singleton = class << Analytics::LiveState; self; end

    analytics_live_state_singleton.alias_method :__test_original_broadcast_later, :broadcast_later
    analytics_live_state_singleton.define_method(:broadcast_later) do |site: nil, **|
      captured_sites << site
    end

    begin
      post "/a/e",
        params: {
          events: [
            {
              name: "pageview",
              site_token: token,
              properties: {
                page: "/pricing",
                url: "https://docs.example.test/pricing",
                title: "Pricing",
                referrer: "",
                screen_size: "1440x900"
              },
              time: Time.current.iso8601
            }
          ]
        },
        as: :json,
        headers: BROWSER_HEADERS
    ensure
      analytics_live_state_singleton.alias_method :broadcast_later, :__test_original_broadcast_later
      analytics_live_state_singleton.remove_method :__test_original_broadcast_later
    end

    assert_response :success
    assert_includes captured_sites, site
  end

  test "first-party pageview tracking uses the bootstrapped default analytics site in singleton mode" do
    host! "localhost:3000"
    site = Analytics::Bootstrap.ensure_default_site!(host: "localhost")

    perform_analytics_jobs do
      bootstrap_and_track_pageview(tracked_page_path, title: "About")
    end

    assert_response :success

    visit = Ahoy::Visit.order(:id).last
    event = Ahoy::Event.order(:id).last

    assert_not_nil site
    assert_equal "localhost", site.canonical_hostname
    assert_equal site.id, visit.analytics_site_id
    assert_equal site.id, event.analytics_site_id
    assert_equal site.boundaries.find_by(primary: true)&.id, visit.analytics_site_boundary_id
  end

  test "separate browsers with the same ip and user agent get distinct anonymous visits" do
    browser_a = open_session
    browser_b = open_session

    perform_analytics_jobs do
      bootstrap_and_track_pageview(tracked_page_path, title: "About", session: browser_a)
    end
    perform_analytics_jobs do
      bootstrap_and_track_pageview(tracked_page_path, title: "About", session: browser_b)
    end

    assert_equal 2, Ahoy::Visit.count

    visits = Ahoy::Visit.order(:id).last(2)
    assert_equal 2, visits.map(&:browser_id).compact.uniq.size
    assert_equal 2, visits.map(&:visitor_token).compact.uniq.size
    assert_equal 2, visits.map(&:analytics_profile_id).compact.uniq.size
  end

  test "cookieless event ingestion ignores spoofed client tokens" do
    perform_analytics_jobs do
      bootstrap_and_track_pageview(tracked_page_path, title: "About")
    end
    visit = Ahoy::Visit.order(:id).last

    assert_no_difference -> { Ahoy::Visit.count } do
      assert_difference -> { Ahoy::Event.count }, +1 do
        post "/a/e",
          params: {
            visit_token: SecureRandom.uuid,
            visitor_token: SecureRandom.uuid,
            events: [
              {
                name: "engagement",
                properties: {
                  page: tracked_page_path,
                  url: tracked_page_url,
                  title: "About",
                  referrer: "",
                  screen_size: "1440x900"
                },
                time: Time.current.iso8601
              }
            ]
          },
          as: :json,
          headers: BROWSER_HEADERS
      end
    end

    assert_response :success
    assert_equal visit.id, Ahoy::Event.order(:id).last.visit_id
  end

  test "non-engagement event creates a visit and backfills landing page and screen size" do
    assert_difference -> { Ahoy::Visit.count }, +1 do
      assert_difference -> { Ahoy::Event.count }, +1 do
        post "/a/e",
          params: {
            events: [
              {
                name: "Signup",
                properties: {
                  page: "/about",
                  url: about_url,
                  title: "About",
                  referrer: "",
                  screen_size: "1440x900"
                },
                time: Time.current.iso8601
              }
            ]
          },
          as: :json,
          headers: BROWSER_HEADERS
      end
    end

    assert_response :success

    visit = Ahoy::Visit.order(:id).last
    assert_not_nil visit
    assert_equal about_url, visit.landing_page
    assert_equal URI.parse(about_url).host, visit.hostname
    assert_equal "Desktop", visit.screen_size
  end

  test "ahoy events controller seeds the analytics browser cookie" do
    post "/a/e",
      params: {
        events: [
          {
            name: "Signup",
            properties: {
              page: "/about",
              url: about_url,
              title: "About",
              referrer: "",
              screen_size: "1440x900"
            },
            time: Time.current.iso8601
          }
        ]
      },
      as: :json,
      headers: BROWSER_HEADERS

    assert_response :success
    assert_includes response.headers["Set-Cookie"].to_s, Analytics::BrowserIdentity::COOKIE_NAME
  end

  test "cookieless event ingestion reuses the recent visit across daily rotation" do
    visit = nil

    travel_to Time.utc(2026, 3, 25, 23, 59, 50) do
      perform_analytics_jobs do
        bootstrap_and_track_pageview(tracked_page_path, title: "About")
      end
      visit = Ahoy::Visit.order(:id).last
    end

    travel_to Time.utc(2026, 3, 26, 0, 0, 10) do
      assert_no_difference -> { Ahoy::Visit.count } do
        assert_difference -> { Ahoy::Event.count }, +1 do
          post "/a/e",
            params: {
              events: [
                {
                  name: "engagement",
                  properties: {
                    page: tracked_page_path,
                    url: tracked_page_url,
                    title: "About",
                    referrer: "",
                    screen_size: "1440x900"
                  },
                  time: Time.current.iso8601
                }
              ]
            },
            as: :json,
            headers: BROWSER_HEADERS
        end
      end
    end

    assert_response :success
    assert_equal visit.id, Ahoy::Event.order(:id).last.visit_id
    assert_equal visit.id, Ahoy::Visit.order(:id).last.id
  end

  test "cookieless engagement does not create a new visit after the session window expires" do
    travel_to Time.utc(2026, 3, 25, 10, 0, 0) do
      perform_analytics_jobs do
        bootstrap_and_track_pageview(tracked_page_path, title: "About")
      end
    end

    expired_visit = Ahoy::Visit.order(:id).last

    travel_to Time.utc(2026, 3, 25, 10, 31, 0) do
      assert_no_difference -> { Ahoy::Visit.count } do
        assert_no_difference -> { Ahoy::Event.count } do
          post "/a/e",
            params: {
              events: [
                {
                  name: "engagement",
                  properties: {
                    page: tracked_page_path,
                    url: tracked_page_url,
                    title: "About",
                    referrer: "",
                    screen_size: "1440x900"
                  },
                  time: Time.current.iso8601
                }
              ]
            },
            as: :json,
            headers: BROWSER_HEADERS
        end
      end
    end

    assert_response :success
    assert_equal expired_visit.id, Ahoy::Visit.order(:id).last.id
  end

  test "logout forces a new anonymous visit on next tracked page" do
    identity, = create_tenant(
      email: "analytics-logout-#{SecureRandom.hex(4)}@example.com",
      name: "Analytics Logout"
    )

    perform_analytics_jobs do
      bootstrap_and_track_pageview(tracked_page_path, title: "About")
    end
    initial_visit = Ahoy::Visit.order(:id).last

    assert_no_difference -> { Ahoy::Visit.count } do
      post identity_session_path, params: {
        identity: {
          email: identity.email,
          password: "password123"
        }
      }, headers: BROWSER_HEADERS
    end

    assert_redirected_to app_path
    assert_equal identity.id, initial_visit.reload.user_id

    assert_no_difference -> { Ahoy::Visit.count } do
      delete destroy_identity_session_path, headers: BROWSER_HEADERS
    end

    assert_redirected_to root_path

    perform_analytics_jobs do
      assert_difference -> { Ahoy::Visit.count }, +1 do
        assert_difference -> { Ahoy::Event.count }, +1 do
          bootstrap_and_track_pageview(tracked_page_path, title: "About")
        end
      end
    end

    next_visit = Ahoy::Visit.order(:id).last
    assert_not_equal initial_visit.id, next_visit.id
    assert_nil next_visit.user_id
    assert_equal initial_visit.visitor_token, next_visit.visitor_token
  end

  test "signing in as a different user after logout forces a new visit" do
    first_identity, = create_tenant(
      email: "analytics-switch-a-#{SecureRandom.hex(4)}@example.com",
      name: "Analytics Switch A"
    )
    second_identity, = create_tenant(
      email: "analytics-switch-b-#{SecureRandom.hex(4)}@example.com",
      name: "Analytics Switch B"
    )

    perform_analytics_jobs do
      bootstrap_and_track_pageview(tracked_page_path, title: "About")
    end
    initial_visit = Ahoy::Visit.order(:id).last

    post identity_session_path, params: {
      identity: {
        email: first_identity.email,
        password: "password123"
      }
    }, headers: BROWSER_HEADERS

    assert_redirected_to app_path
    assert_equal first_identity.id, initial_visit.reload.user_id

    delete destroy_identity_session_path, headers: BROWSER_HEADERS

    assert_redirected_to root_path

    assert_no_difference -> { Ahoy::Visit.count } do
      post identity_session_path, params: {
        identity: {
          email: second_identity.email,
          password: "password123"
        }
      }, headers: BROWSER_HEADERS
    end

    assert_redirected_to app_path
    assert_equal first_identity.id, initial_visit.reload.user_id
    assert_equal true, request.session["analytics.force_new_visit"]

    perform_analytics_jobs do
      assert_difference -> { Ahoy::Visit.count }, +1 do
        assert_difference -> { Ahoy::Event.count }, +1 do
          bootstrap_and_track_pageview(about_path, title: "About")
        end
      end
    end

    next_visit = Ahoy::Visit.order(:id).last
    assert_not_equal initial_visit.id, next_visit.id
    assert_equal second_identity.id, next_visit.user_id
    assert_equal initial_visit.visitor_token, next_visit.visitor_token
  end

  private
    def tracked_page_path
      about_path
    end

    def tracked_page_url
      about_url
    end

    def bootstrap_and_track_pageview(path, title:, headers: BROWSER_HEADERS, referrer: "", session: self)
      session.get path, headers: headers
    end

    def perform_analytics_jobs(&block)
      perform_enqueued_jobs(
        only: [
          Analytics::ProfileResolutionJob,
          Analytics::VisitProjectionJob
        ],
        &block
      )
    end
end
