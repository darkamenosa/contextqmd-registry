# frozen_string_literal: true

module Version::DocsQuerying
  CHUNK_TARGET_TOKENS = 800
  CHUNK_OVERLAP_LINES = 2

  def query_docs(query:, max_tokens:, mode: :full)
    matched_pages = search_pages(query)

    results = if mode == :fast
      pack_pages_fast(matched_pages, max_tokens)
    else
      pack_chunks(split_and_rank_chunks(matched_pages, query), max_tokens)
    end

    {
      results: results,
      total_matches: matched_pages.size
    }
  end

  private

    def search_pages(query)
      pages.search_content(query).limit(50)
    end

    def split_and_rank_chunks(matched_pages, query)
      query_terms = query.downcase.split(/\s+/).reject { |term| term.length < 2 }
      chunks = []

      matched_pages.each_with_index do |page, page_rank|
        content = page.description.to_s
        page_tokens = estimate_tokens(content)

        if page_tokens <= CHUNK_TARGET_TOKENS * 1.5
          chunks << build_chunk(page, content, 0, page_rank, query_terms)
        else
          split_page_into_chunks(page, content, page_rank, query_terms).each do |chunk|
            chunks << chunk
          end
        end
      end

      chunks.sort_by { |chunk| [ chunk[:page_rank], -chunk[:score] ] }
    end

    def split_page_into_chunks(page, content, page_rank, query_terms)
      sections = split_by_headings(content)
      chunks = []

      sections.each_with_index do |section, index|
        section_tokens = estimate_tokens(section[:text])

        if section_tokens <= CHUNK_TARGET_TOKENS * 1.5
          chunks << build_chunk(page, section[:text], index, page_rank, query_terms, heading: section[:heading])
        else
          paragraph_chunks(page, section, index, page_rank, query_terms).each do |chunk|
            chunks << chunk
          end
        end
      end

      chunks
    end

    def paragraph_chunks(page, section, index, page_rank, query_terms)
      chunks = []
      current_paragraphs = []
      current_tokens = 0

      section[:text].split(/\n\n+/).each do |paragraph|
        paragraph_tokens = estimate_tokens(paragraph)

        if current_tokens + paragraph_tokens > CHUNK_TARGET_TOKENS && current_paragraphs.any?
          chunks << build_chunk(
            page,
            current_paragraphs.join("\n\n"),
            index,
            page_rank,
            query_terms,
            heading: section[:heading]
          )

          current_paragraphs = current_paragraphs.last(CHUNK_OVERLAP_LINES)
          current_tokens = estimate_tokens(current_paragraphs.join("\n\n"))
        end

        current_paragraphs << paragraph
        current_tokens += paragraph_tokens
      end

      if current_paragraphs.any?
        chunks << build_chunk(
          page,
          current_paragraphs.join("\n\n"),
          index,
          page_rank,
          query_terms,
          heading: section[:heading]
        )
      end

      chunks
    end

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

      if current_lines.any?
        sections << { heading: current_heading, text: current_lines.join }
      end

      sections.presence || [ { heading: nil, text: content } ]
    end

    def build_chunk(page, text, chunk_index, page_rank, query_terms, heading: nil)
      {
        page_uid: page.page_uid,
        path: page.path,
        title: heading ? "#{page.title} > #{heading}" : page.title,
        url: page.url,
        content_md: text.strip,
        page_rank: page_rank,
        score: score_chunk(text, query_terms),
        chunk_index: chunk_index
      }
    end

    def score_chunk(text, query_terms)
      if query_terms.empty?
        0
      else
        text_lower = text.downcase
        matches = query_terms.count { |term| text_lower.include?(term) }
        matches.to_f / query_terms.size
      end
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

    def pack_pages_fast(matched_pages, max_tokens)
      packed = []
      token_count = 0

      matched_pages.each do |page|
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
