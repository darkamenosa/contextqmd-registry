# frozen_string_literal: true

class SitemapsController < ApplicationController
  include SeoHelper

  allow_unauthenticated_access
  disallow_account_scope

  PER_SITEMAP = 50_000

  # GET /sitemap.xml — sitemap index listing all sub-sitemaps
  def index
    @host = "https://#{canonical_host}"

    lib_shards = library_shard_count
    page_shards = page_shard_count

    @sitemaps = []
    @sitemaps << "#{@host}/sitemaps/static.xml"
    lib_shards.times { |i| @sitemaps << "#{@host}/sitemaps/libraries/#{i + 1}.xml" }
    page_shards.times { |i| @sitemaps << "#{@host}/sitemaps/pages/#{i + 1}.xml" }

    expires_in 6.hours, public: true
    render formats: :xml
  end

  # GET /sitemaps/static.xml — homepage, marketing pages, rankings
  def static_pages
    @host = "https://#{canonical_host}"
    expires_in 24.hours, public: true
    render formats: :xml
  end

  # GET /sitemaps/libraries/:page — paginated library landing pages
  def libraries
    page_num = validated_page_num(library_shard_count)
    return head(:not_found) unless page_num

    @host = "https://#{canonical_host}"
    offset = (page_num - 1) * PER_SITEMAP

    @libraries = Library.select(:slug, :updated_at)
                        .order(:id)
                        .offset(offset)
                        .limit(PER_SITEMAP)

    expires_in 1.hour, public: true
    render formats: :xml
  end

  # GET /sitemaps/pages/:page — paginated doc pages (default version only)
  # Uses default_version as the stable canonical target for SEO.
  # This intentionally differs from best_version (UI fallback logic).
  def pages
    page_num = validated_page_num(page_shard_count)
    return head(:not_found) unless page_num

    @host = "https://#{canonical_host}"
    offset = (page_num - 1) * PER_SITEMAP

    default_version_ids = Version.joins(:library)
                                 .where("versions.version = libraries.default_version")
                                 .select(:id)

    @pages = Page.where(version_id: default_version_ids)
                 .joins(version: :library)
                 .select(
                   "pages.page_uid",
                   "pages.updated_at",
                   "libraries.slug AS library_slug",
                   "versions.version AS version_number"
                 )
                 .order("pages.id")
                 .offset(offset)
                 .limit(PER_SITEMAP)

    expires_in 1.hour, public: true
    render formats: :xml
  end

  private

    # Use versions.pages_count counter cache instead of counting millions of page rows
    def default_version_pages_count
      Version.joins(:library)
             .where("versions.version = libraries.default_version")
             .sum(:pages_count)
    end

    def library_shard_count
      @library_shard_count ||= [ (Library.count.to_f / PER_SITEMAP).ceil, 0 ].max
    end

    def page_shard_count
      @page_shard_count ||= [ (default_version_pages_count.to_f / PER_SITEMAP).ceil, 0 ].max
    end

    # Returns validated page number, or nil if out of range
    def validated_page_num(max_shards)
      num = params[:page].to_i
      return nil if num < 1 || num > [ max_shards, 1 ].max

      num
    end

    # Percent-encode each segment of a path for use in sitemap <loc> URLs
    def encode_path_segments(path)
      path.split("/").map { |segment| CGI.escape(segment).gsub("+", "%20") }.join("/")
    end
    helper_method :encode_path_segments
end
