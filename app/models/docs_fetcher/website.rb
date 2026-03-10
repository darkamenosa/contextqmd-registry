# frozen_string_literal: true

module DocsFetcher
  # Strategy entrypoint for website crawling.
  # Delegates to RubyRunner (BFS HTML crawler) or NodeRunner (future Node child).
  #
  # This is NOT the crawler itself — it selects the right runner.
  class Website
    def fetch(crawl_request, on_progress: nil)
      runner = select_runner
      runner.fetch(crawl_request, on_progress: on_progress)
    end

    private

      def select_runner
        # Future: check if Node runner is available and if crawl needs JS rendering.
        # For now, always use the Ruby BFS crawler.
        RubyRunner.new
      end
  end
end
