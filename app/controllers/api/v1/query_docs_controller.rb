# frozen_string_literal: true

module Api
  module V1
    class QueryDocsController < BaseController
      skip_before_action :authenticate_api_token!
      rate_limit to: 60, within: 1.minute, by: -> { request.remote_ip }, only: :create
      include Concerns::LibraryVersionLookup

      before_action :find_library_and_version!

      # POST /api/v1/libraries/:namespace/:name/versions/:version/query
      #
      # Params:
      #   query      - search query string (required)
      #   max_tokens - approximate token budget for response (default: 5000)
      #   mode       - "fast" (BM25, whole pages) or "full" (chunk splitting + scoring, default)
      #
      # Returns matching page chunks packed within the token budget, most relevant first.
      # In "fast" mode, returns whole pages without chunk splitting (~2x faster).
      # In "full" mode (default), large pages are split into ~800-token chunks.
      def create
        query = params[:query].to_s.strip
        max_tokens = (params[:max_tokens] || 5000).to_i.clamp(500, 50_000)
        mode = params[:mode].to_s == "fast" ? :fast : :full

        if query.blank?
          return render_error(code: "invalid_query", message: "query parameter is required", status: :unprocessable_entity)
        end

        pages = search_pages(query)

        packed = if mode == :fast
          pack_pages_fast(pages, max_tokens)
        else
          chunks = split_and_rank_chunks(pages, query)
          pack_chunks(chunks, max_tokens)
        end

        render_data(
          packed,
          meta: {
            query: query,
            max_tokens: max_tokens,
            mode: mode.to_s,
            results: packed.size,
            total_matches: pages.size
          }
        )
      end

      private

        CHUNK_TARGET_TOKENS = 800
        CHUNK_OVERLAP_LINES = 2

        def search_pages(query)
          @version.pages.search_content(query).limit(50)
        end

        # Split pages into chunks and score each chunk against the query.
        def split_and_rank_chunks(pages, query)
          query_terms = query.downcase.split(/\s+/).reject { |t| t.length < 2 }
          chunks = []

          pages.each_with_index do |page, page_rank|
            content = page.description.to_s
            page_tokens = estimate_tokens(content)

            if page_tokens <= CHUNK_TARGET_TOKENS * 1.5
              # Small page — keep as single chunk
              chunks << build_chunk(page, content, 0, page_rank, query_terms)
            else
              # Large page — split into heading-aware chunks
              split_page_into_chunks(page, content, page_rank, query_terms).each do |chunk|
                chunks << chunk
              end
            end
          end

          # Sort: page rank first (from pg_search), then chunk relevance
          chunks.sort_by { |c| [ c[:page_rank], -c[:score] ] }
        end

        def split_page_into_chunks(page, content, page_rank, query_terms)
          sections = split_by_headings(content)
          chunks = []

          sections.each_with_index do |section, idx|
            section_tokens = estimate_tokens(section[:text])

            if section_tokens <= CHUNK_TARGET_TOKENS * 1.5
              chunks << build_chunk(page, section[:text], idx, page_rank, query_terms,
                heading: section[:heading])
            else
              # Further split large sections by paragraph groups
              paragraphs = section[:text].split(/\n\n+/)
              current_lines = []
              current_tokens = 0

              paragraphs.each do |para|
                para_tokens = estimate_tokens(para)

                if current_tokens + para_tokens > CHUNK_TARGET_TOKENS && current_lines.any?
                  text = current_lines.join("\n\n")
                  chunks << build_chunk(page, text, idx, page_rank, query_terms,
                    heading: section[:heading])
                  # Keep last few lines for overlap context
                  current_lines = current_lines.last(CHUNK_OVERLAP_LINES)
                  current_tokens = estimate_tokens(current_lines.join("\n\n"))
                end

                current_lines << para
                current_tokens += para_tokens
              end

              if current_lines.any?
                text = current_lines.join("\n\n")
                chunks << build_chunk(page, text, idx, page_rank, query_terms,
                  heading: section[:heading])
              end
            end
          end

          chunks
        end

        # Split content by markdown headings (##, ###, ####)
        def split_by_headings(content)
          sections = []
          current_heading = nil
          current_lines = []

          content.each_line do |line|
            if line.match?(/\A\#{2,4}\s+/)
              if current_lines.any?
                sections << { heading: current_heading, text: current_lines.join }
              end
              current_heading = line.strip.sub(/\A#+\s+/, "")
              current_lines = [ line ]
            else
              current_lines << line
            end
          end

          sections << { heading: current_heading, text: current_lines.join } if current_lines.any?
          sections.presence || [ { heading: nil, text: content } ]
        end

        def build_chunk(page, text, chunk_idx, page_rank, query_terms, heading: nil)
          {
            page_uid: page.page_uid,
            path: page.path,
            title: heading ? "#{page.title} > #{heading}" : page.title,
            url: page.url,
            content_md: text.strip,
            page_rank: page_rank,
            score: score_chunk(text, query_terms),
            chunk_index: chunk_idx
          }
        end

        # Simple keyword overlap score for ranking chunks within a page
        def score_chunk(text, query_terms)
          return 0 if query_terms.empty?

          text_lower = text.downcase
          matches = query_terms.count { |term| text_lower.include?(term) }
          matches.to_f / query_terms.size
        end

        def pack_chunks(chunks, max_tokens)
          packed = []
          token_count = 0

          chunks.each do |chunk|
            chunk_tokens = estimate_tokens(chunk[:content_md])
            break if token_count + chunk_tokens > max_tokens && packed.any?

            packed << chunk.except(:page_rank, :score, :chunk_index)
            token_count += chunk_tokens
          end

          packed
        end

        # Fast mode: return whole pages without chunk splitting.
        # BM25 ranking from pg_search is already good; just pack within budget.
        def pack_pages_fast(pages, max_tokens)
          packed = []
          token_count = 0

          pages.each do |page|
            content = page.description.to_s
            page_tokens = estimate_tokens(content)
            break if token_count + page_tokens > max_tokens && packed.any?

            packed << {
              page_uid: page.page_uid,
              path: page.path,
              title: page.title,
              url: page.url,
              content_md: content.strip
            }
            token_count += page_tokens
          end

          packed
        end

        def estimate_tokens(text)
          (text.to_s.bytesize / 4.0).ceil
        end
    end
  end
end
