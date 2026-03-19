# frozen_string_literal: true

# Sitemap index linking to child sitemaps (Shopify pattern).
# GET /sitemap.xml
#
# Child sitemaps are in the Sitemaps namespace:
#   - Sitemaps::StaticController   (marketing pages)
#   - Sitemaps::LibrariesController (library landing pages, ID-range pagination)
#   - Sitemaps::PagesController    (doc pages, ID-range pagination)
#
# The index computation (plucking IDs to build chunks) is cached in Rails.cache
# because plucking millions of page IDs is expensive. Cache key includes the
# latest timestamp so new content invalidates immediately.
class SitemapsController < ApplicationController
  include SeoHelper

  allow_unauthenticated_access
  disallow_account_scope

  PER_SITEMAP = 5_000

  private

    def default_host
      @default_host ||= request.base_url
    end

  public

  def show
    latest_update = [
      Library.not_cancelled.maximum(:updated_at),
      Page.maximum(:updated_at),
      Time.current.beginning_of_day
    ].compact.max

    if stale?(last_modified: latest_update, public: true)
      @host = default_host
      @latest_update = latest_update
      @sitemaps = build_sitemap_entries(latest_update)
      expires_in 6.hours, public: true
      render formats: :xml
    end
  end

  private

    def build_sitemap_entries(cache_version)
      lib_lastmod = Library.not_cancelled.maximum(:updated_at)
      page_lastmod = Page.maximum(:updated_at)

      entries = []
      entries << { loc: "#{@host}/sitemap_static_1.xml", lastmod: Time.current.beginning_of_day }
      entries.concat(library_entries(cache_version, lib_lastmod))
      entries.concat(page_entries(cache_version, page_lastmod))
      entries
    end

    def library_entries(cache_version, lastmod)
      chunks = Rails.cache.fetch("sitemap:library_chunks:#{cache_version.to_i}") do
        Library.not_cancelled.order(:id).pluck(:id).each_slice(PER_SITEMAP).map { |c| [ c.first, c.last ] }
      end

      chunks.each_with_index.map do |range, i|
        # Use raw & — ERB will escape to &amp; in the XML template
        { loc: "#{@host}/sitemap_libraries_#{i + 1}.xml?from=#{range.first}&to=#{range.last}", lastmod: lastmod }
      end
    end

    def page_entries(cache_version, lastmod)
      chunks = Rails.cache.fetch("sitemap:page_chunks:#{cache_version.to_i}") do
        default_version_ids = Version.joins(:library)
                                     .merge(Library.indexable)
                                     .where("versions.version = libraries.default_version")
                                     .select(:id)

        Page.where(version_id: default_version_ids).order(:id).pluck(:id)
            .each_slice(PER_SITEMAP).map { |c| [ c.first, c.last ] }
      end

      chunks.each_with_index.map do |range, i|
        { loc: "#{@host}/sitemap_pages_#{i + 1}.xml?from=#{range.first}&to=#{range.last}", lastmod: lastmod }
      end
    end
end
