# frozen_string_literal: true

module DocsFetcher
  class Git
    # GitHub-specific URL parsing for github.com repositories.
    class Github < Git
      private

        def normalize_git_url(url)
          uri = URI.parse(url.strip)
          parts = uri.path.delete_prefix("/").split("/").first(2)
          clean_path = parts.join("/").delete_suffix(".git")
          "https://github.com/#{clean_path}.git"
        end

        def extract_branch_from_url(url)
          parts = URI.parse(url.strip).path.delete_prefix("/").split("/")
          parts[3] if parts[2] == "tree"
        rescue URI::InvalidURIError
          nil
        end

        def build_file_url(source_url, rel_path, branch_or_tag)
          parts = URI.parse(source_url.strip).path.delete_prefix("/").split("/")
          ref = branch_or_tag || "main"
          "https://github.com/#{parts[0]}/#{parts[1]&.delete_suffix('.git')}/blob/#{ref}/#{rel_path}"
        end

        def normalize_homepage_url(source_url)
          parts = URI.parse(source_url.strip).path.delete_prefix("/").split("/")
          "https://github.com/#{parts.first(2).join('/')}"
        end
    end
  end
end
