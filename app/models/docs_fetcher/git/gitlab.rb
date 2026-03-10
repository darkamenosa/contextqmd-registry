# frozen_string_literal: true

module DocsFetcher
  class Git
    # GitLab-specific URL parsing for gitlab.com and self-hosted GitLab instances.
    class Gitlab < Git
      private

        def normalize_git_url(url)
          uri = URI.parse(url.strip)
          host = uri.host&.downcase
          parts = uri.path.delete_prefix("/").split("/")
          separator_idx = parts.index("-")
          clean_parts = separator_idx ? parts[0...separator_idx] : parts
          clean_path = clean_parts.join("/").delete_suffix(".git")
          "https://#{host}/#{clean_path}.git"
        end

        def extract_branch_from_url(url)
          parts = URI.parse(url.strip).path.delete_prefix("/").split("/")
          separator_idx = parts.index("-")
          parts[separator_idx + 2] if separator_idx && parts[separator_idx + 1] == "tree"
        rescue URI::InvalidURIError
          nil
        end

        def extract_owner_repo(url)
          uri = URI.parse(url.strip)
          parts = uri.path.delete_prefix("/").split("/")
          separator_idx = parts.index("-")
          project_parts = separator_idx ? parts[0...separator_idx] : parts
          owner = project_parts[0...-1].join("/")
          repo_name = project_parts.last&.delete_suffix(".git")
          raise ArgumentError, "Invalid git URL: #{url}" unless owner.present? && repo_name.present?
          [ owner.downcase, repo_name.downcase ]
        end

        def build_file_url(source_url, rel_path, branch_or_tag)
          uri = URI.parse(source_url.strip)
          host = uri.host&.downcase
          parts = uri.path.delete_prefix("/").split("/")
          separator_idx = parts.index("-")
          project_path = (separator_idx ? parts[0...separator_idx] : parts).join("/")
          ref = branch_or_tag || "main"
          "https://#{host}/#{project_path}/-/blob/#{ref}/#{rel_path}"
        end
    end
  end
end
