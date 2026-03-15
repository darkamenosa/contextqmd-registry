# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "rubygems/package"
require "securerandom"
require "zlib"

class DocsBundle
  FORMAT = "tar.gz"
  MIME_TYPE = "application/octet-stream"
  FILE_MODE = 0o644
  DIRECTORY_MODE = 0o755
  FIXED_MTIME = Time.utc(2026, 3, 12, 0, 0, 0).freeze

  def self.refresh!(version, profile: "full")
    new(version: version, profile: profile).refresh!
  end

  def self.storage_root
    root = Rails.root.join("tmp", "contextqmd", "bundles")

    if Rails.env.test?
      worker_id = ENV["TEST_ENV_NUMBER"].presence || Process.pid
      root.join(worker_id.to_s)
    else
      root
    end
  end

  def self.path_for(version:, profile:, format: FORMAT)
    storage_root.join(
      safe_path_component(version.library.slug),
      safe_path_component(version.version),
      "#{safe_path_component(profile)}.#{safe_path_component(format)}"
    )
  end

  def self.safe_path_component(value)
    component = value.to_s
    return component if component.present? && !component.in?([ ".", ".." ]) && !component.include?("/") && !component.include?("\\")

    raise ArgumentError, "Unsafe bundle path component: #{component.inspect}"
  end
  private_class_method :safe_path_component

  def initialize(version:, profile: "full")
    @version = version
    @profile = profile
  end

  attr_reader :version, :profile

  def refresh!
    FileUtils.mkdir_p(file_path.dirname)

    temp_path = file_path.dirname.join(".#{file_path.basename}.#{SecureRandom.hex(8)}.tmp")
    write_archive(temp_path)

    bundle = version.bundles.find_or_initialize_by(profile: profile)
    FileUtils.mv(temp_path, file_path)
    publish_bundle(bundle)
    bundle
  ensure
    FileUtils.rm_f(temp_path) if temp_path.present? && File.exist?(temp_path)
  end

  def file_path
    self.class.path_for(version: version, profile: profile)
  end

  private

    def write_archive(path)
      File.open(path, "wb") do |file|
        gzip = Zlib::GzipWriter.new(file)
        gzip.mtime = 0

        begin
          write_tar_archive(gzip)
        ensure
          gzip.close
        end
      end
    end

    def write_tar_archive(io)
      write_directory_entry(io, "pages")
      write_file_entry(io, "manifest.json", manifest_json)
      write_file_entry(io, "page-index.json", page_index_json)

      ordered_pages.each do |page|
        write_file_entry(io, "pages/#{bundle_page_entry(page)}", page.description.to_s)
      end

      io.write("\0" * 1024)
    end

    def manifest_json
      JSON.generate(
        {
          schema_version: "1.0",
          slug: version.library.slug,
          display_name: version.library.display_name,
          version: version.version,
          channel: version.channel,
          generated_at: version.generated_at&.iso8601,
          doc_count: ordered_pages.size,
          source: source_json,
          page_index: {
            path: "page-index.json",
            sha256: "sha256:#{Digest::SHA256.hexdigest(page_index_json)}"
          },
          profiles: {},
          source_policy: source_policy_json,
          provenance: provenance_json
        }
      )
    end

    def page_index_json
      @page_index_json ||= JSON.generate(ordered_pages.map { |page| page_summary_json(page) })
    end

    def ordered_pages
      @ordered_pages ||= version.pages.order(page_uid: :asc).to_a
    end

    def source_json
      return nil unless version.fetch_recipe

      {
        type: version.fetch_recipe.source_type,
        url: version.fetch_recipe.url
      }
    end

    def source_policy_json
      return nil unless version.library.source_policy

      {
        license_name: version.library.source_policy.license_name,
        license_status: version.library.source_policy.license_status,
        mirror_allowed: version.library.source_policy.mirror_allowed,
        origin_fetch_allowed: version.library.source_policy.origin_fetch_allowed,
        attribution_required: version.library.source_policy.attribution_required
      }
    end

    def provenance_json
      {
        normalizer_version: version.fetch_recipe&.normalizer_version,
        splitter_version: version.fetch_recipe&.splitter_version,
        manifest_checksum: version.manifest_checksum
      }
    end

    def page_summary_json(page)
      {
        page_uid: page.page_uid,
        bundle_path: bundle_page_entry(page),
        path: page.path,
        title: page.title,
        url: page.url,
        checksum: page.checksum,
        bytes: page.bytes,
        headings: page.headings,
        updated_at: page.updated_at&.iso8601
      }
    end

    def bundle_page_entry(page)
      page_uid = page.page_uid.to_s

      if page_uid.blank? || page_uid.start_with?("/") || page_uid.include?("\\") || page_uid.split("/").include?("..")
        raise ArgumentError, "Unsafe page_uid for bundle path: #{page_uid.inspect}"
      end

      "#{Digest::SHA256.hexdigest(page_uid)}.md"
    end

    def write_directory_entry(io, name)
      io.write(tar_header(name: name, mode: DIRECTORY_MODE, size: 0, typeflag: "5"))
    end

    def write_file_entry(io, name, content)
      data = content.to_s.b

      io.write(tar_header(name: name, mode: FILE_MODE, size: data.bytesize))
      io.write(data)
      io.write("\0" * padding_size(data.bytesize))
    end

    def tar_header(name:, mode:, size:, typeflag: "0")
      entry_name, prefix = split_name(name)

      Gem::Package::TarHeader.new(
        name: entry_name,
        prefix: prefix,
        mode: mode,
        uid: 0,
        gid: 0,
        size: size,
        mtime: FIXED_MTIME,
        typeflag: typeflag,
        uname: "",
        gname: ""
      ).to_s
    end

    def split_name(name)
      return [ name, "" ] if name.bytesize <= 100

      prefix, entry_name = name.rpartition("/").values_at(0, 2)

      if prefix.blank? || entry_name.bytesize > 100 || prefix.bytesize > 155
        raise ArgumentError, "Bundle entry path is too long: #{name.inspect}"
      end

      [ entry_name, prefix ]
    end

    def padding_size(bytesize)
      (512 - (bytesize % 512)) % 512
    end

    def publish_bundle(bundle)
      checksum = "sha256:#{Digest::SHA256.file(file_path).hexdigest}"
      size_bytes = File.size(file_path)

      bundle.assign_attributes(
        format: FORMAT,
        status: "processing",
        error_message: nil
      )
      bundle.save! if bundle.new_record? || bundle.changed?

      Current.with_account(bundle.account) do
        blob = find_or_upload_package_blob(bundle, checksum: checksum)
        attach_package_blob(bundle, blob)
      end

      bundle.update!(
        format: FORMAT,
        sha256: checksum,
        size_bytes: size_bytes,
        status: "ready",
        error_message: nil
      )
    end

    def find_or_upload_package_blob(bundle, checksum:)
      key = bundle.package_key(checksum: checksum)

      if blob = ActiveStorage::Blob.find_by(key: key, service_name: bundle.package_service_name.to_s)
        blob
      else
        upload_package_blob(bundle, key)
      end
    end

    def attach_package_blob(bundle, blob)
      return if bundle.package.attached? && bundle.package.blob == blob

      previous_blob = bundle.package.blob if bundle.package.attached?
      bundle.package.attach(blob)
      purge_blob_if_unattached(previous_blob)
    end

    def upload_package_blob(bundle, key)
      File.open(file_path, "rb") do |package_io|
        ActiveStorage::Blob.create_and_upload!(
          key: key,
          io: package_io,
          filename: bundle.filename,
          content_type: MIME_TYPE,
          identify: false,
          service_name: bundle.package_service_name
        )
      end
    end

    def purge_blob_if_unattached(blob)
      if blob.present? && blob.attachments.reload.none?
        blob.purge
      end
    end
end
