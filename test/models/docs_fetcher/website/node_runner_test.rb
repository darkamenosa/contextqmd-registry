# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class DocsFetcher::Website::NodeRunnerTest < ActiveSupport::TestCase
  setup do
    @original_checkout = ProxyPool.method(:checkout)
  end

  test "fetch uses website-scoped proxies, forwards progress, and records success" do
    runner = DocsFetcher::Website::NodeRunner.new
    script_path = write_node_script(<<~JAVASCRIPT)
      import { mkdir, writeFile } from "node:fs/promises";
      import { dirname } from "node:path";

      const inputChunks = [];
      for await (const chunk of process.stdin) inputChunks.push(chunk);

      const input = JSON.parse(inputChunks.join(""));

      console.log(JSON.stringify({
        type: "progress",
        message: "Rendering browser page",
        current: 1,
        total: 2
      }));

      await mkdir(dirname(input.output_path), { recursive: true });
      await writeFile(input.output_path, JSON.stringify({
        pages: [
          {
            url: input.url,
            html: "<html><body><main><h1>Guide</h1><p>Hello from the browser.</p><a href='/guide/next'>Next</a></main></body></html>"
          }
        ]
      }));

      console.log(JSON.stringify({
        type: "result",
        output_path: input.output_path
      }));
    JAVASCRIPT
    proxy_lease = build_proxy_lease
    checkout_options = nil
    progress_events = []
    crawl_request = Struct.new(:url, :library_id, :library, :metadata).new(
      "https://docs.example.com/guide",
      nil,
      nil,
      {}
    )

    runner.define_singleton_method(:command) { [ "node", script_path ] }

    ProxyPool.define_singleton_method(:checkout) do |**options|
      checkout_options = options
      proxy_lease
    end

    result = runner.fetch(
      crawl_request,
      on_progress: ->(message, current: nil, total: nil) { progress_events << [ message, current, total ] }
    )

    assert_equal "website", checkout_options[:scope]
    assert_equal true, checkout_options[:sticky_session]
    assert_equal [ "docs.example.com" ], proxy_lease.successes
    assert_empty proxy_lease.failures
    assert_equal 1, proxy_lease.releases
    assert_includes progress_events, [ "Rendering browser page", 1, 2 ]
    assert_equal "Example", result.display_name
    assert_equal 1, result.pages.size
    assert_equal "guide", result.pages.first[:page_uid]
    assert_includes result.pages.first[:content], "Hello from the browser."
  ensure
    reset_proxy_pool
  end

  test "fetch records proxy failure when node crawler exits with a retryable error" do
    runner = DocsFetcher::Website::NodeRunner.new
    script_path = write_node_script(<<~JAVASCRIPT)
      console.log(JSON.stringify({
        type: "error",
        error_class: "transient",
        message: "Timed out waiting for rendered page"
      }));
      process.exit(1);
    JAVASCRIPT
    proxy_lease = build_proxy_lease
    crawl_request = Struct.new(:url, :library_id, :library, :metadata).new(
      "https://docs.example.com/guide",
      nil,
      nil,
      {}
    )

    runner.define_singleton_method(:command) { [ "node", script_path ] }

    ProxyPool.define_singleton_method(:checkout) { |**_options| proxy_lease }

    error = assert_raises(DocsFetcher::TransientFetchError) do
      runner.fetch(crawl_request)
    end

    assert_includes error.message, "Timed out waiting for rendered page"
    assert_empty proxy_lease.successes
    assert_equal [ [ "DocsFetcher::TransientFetchError", "docs.example.com" ] ], proxy_lease.failures
    assert_equal 1, proxy_lease.releases
  ensure
    reset_proxy_pool
  end

  test "build_payload includes proxy bypass hosts" do
    runner = DocsFetcher::Website::NodeRunner.new
    proxy_config = CrawlProxyConfig.new(
      name: "proxy",
      scheme: "http",
      host: "proxy.example.com",
      port: 8080,
      username: "proxy-user",
      password: "proxy-pass",
      bypass: ".internal.example,localhost"
    )
    crawl_request = Struct.new(:url, :library_id, :library).new(
      "https://docs.example.com/guide",
      nil,
      nil
    )

    payload = runner.send(:build_payload, crawl_request, "/tmp/result.json", proxy_config)

    assert_equal ".internal.example,localhost", payload.dig(:proxy, :bypass)
  end

  test "build_payload includes requested max_pages" do
    runner = DocsFetcher::Website::NodeRunner.new
    crawl_request = Struct.new(:url, :library_id, :library, :metadata).new(
      "https://docs.example.com/guide",
      nil,
      nil,
      { "website_max_pages" => "1" }
    )

    payload = runner.send(:build_payload, crawl_request, "/tmp/result.json", nil)

    assert_equal 1, payload[:max_pages]
  end

  test "fetch_batch renders provided urls and preserves discovered links" do
    runner = DocsFetcher::Website::NodeRunner.new
    script_path = write_node_script(<<~JAVASCRIPT)
      import { mkdir, writeFile } from "node:fs/promises";
      import { dirname } from "node:path";

      const inputChunks = [];
      for await (const chunk of process.stdin) inputChunks.push(chunk);
      const input = JSON.parse(inputChunks.join(""));

      await mkdir(dirname(input.output_path), { recursive: true });
      await writeFile(input.output_path, JSON.stringify({
        pages: input.urls.map((url) => ({
          requested_url: url,
          url,
          html: "<html><body><main><h1>Guide</h1><p>Hello from the browser.</p></main></body></html>",
          links: [url + \"/next\"]
        }))
      }));

      console.log(JSON.stringify({ type: "result", output_path: input.output_path }));
    JAVASCRIPT
    proxy_lease = build_proxy_lease
    crawl_request = Struct.new(:url, :library_id, :library, :metadata).new(
      "https://docs.example.com/guide",
      nil,
      nil,
      {}
    )

    runner.define_singleton_method(:command) { [ "node", script_path ] }
    ProxyPool.define_singleton_method(:checkout) { |**_options| proxy_lease }

    snapshots = runner.fetch_batch(crawl_request, [ "https://docs.example.com/guide" ])

    assert_equal 1, snapshots.size
    assert_equal "https://docs.example.com/guide", snapshots.first[:requested_url]
    assert_equal "guide", snapshots.first.dig(:page, :page_uid)
    assert_includes snapshots.first[:links], "https://docs.example.com/guide/next"
  ensure
    reset_proxy_pool
  end

  test "build_payload ignores non-string bypass values" do
    runner = DocsFetcher::Website::NodeRunner.new
    proxy_config = Struct.new(:bypass) do
      def to_uri
        URI("http://proxy-user:proxy-pass@proxy.example.com:8080")
      end
    end.new({ invalid: true })
    crawl_request = Struct.new(:url, :library_id, :library).new(
      "https://docs.example.com/guide",
      nil,
      nil
    )

    payload = runner.send(:build_payload, crawl_request, "/tmp/result.json", proxy_config)

    assert_equal "http://proxy.example.com:8080", payload.dig(:proxy, :server)
    assert_nil payload.dig(:proxy, :bypass)
  end

  test "build_page keeps rendered pages larger than one megabyte" do
    runner = DocsFetcher::Website::NodeRunner.new
    huge_body = ("Rendered docs. " * 90_000)

    page = runner.send(
      :build_page,
      {
        "url" => "https://docs.example.com/huge",
        "html" => "<html><body><main><h1>Huge Guide</h1><p>#{huge_body}</p></main></body></html>"
      }
    )

    assert_equal "huge", page[:page_uid]
    assert_equal "Huge Guide", page[:title]
    assert_operator page[:content].bytesize, :>, 1_000_000
  end

  private

    def write_node_script(source)
      dir = Dir.mktmpdir("contextqmd-node-runner-test-")
      path = File.join(dir, "runner.mjs")
      File.write(path, source)
      path
    end

    def build_proxy_lease
      proxy_config = Struct.new(:bypass) do
        def to_uri
          URI("http://proxy-user:proxy-pass@proxy.example.com:8080")
        end
      end.new(nil)

      Struct.new(:crawl_proxy_config, :successes, :failures, :releases) do
        def record_success(target_host: nil)
          successes << target_host
        end

        def record_failure(error_class: nil, target_host: nil)
          failures << [ error_class, target_host ]
        end

        def release!
          self.releases += 1
        end
      end.new(proxy_config, [], [], 0)
    end

    def reset_proxy_pool
      ProxyPool.define_singleton_method(:checkout, @original_checkout)
    end
end
