# frozen_string_literal: true

module DocsFetcher
  class Website
    # Future: Node child process for website crawling.
    # Spawns `node script/crawlers/website/index.mjs` with JSON input on stdin,
    # reads NDJSON progress events from stdout, and collects the result artifact.
    #
    # Not yet implemented — Website currently always uses RubyRunner.
    class NodeRunner
      def fetch(_crawl_request, on_progress: nil)
        raise NotImplementedError, "NodeRunner is not yet implemented. Use RubyRunner."
      end
    end
  end
end
