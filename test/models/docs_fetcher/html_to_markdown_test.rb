# frozen_string_literal: true

require "test_helper"

class DocsFetcher::HtmlToMarkdownTest < ActiveSupport::TestCase
  # --- Basic conversion ---

  test "converts simple HTML to markdown" do
    html = <<~HTML
      <html>
        <body>
          <article>
            <h1>Getting Started</h1>
            <p>This is the introduction paragraph with enough text to pass the minimum length threshold for content detection.</p>
            <h2>Installation</h2>
            <p>Run npm install to get started with the package installation process.</p>
          </article>
        </body>
      </html>
    HTML

    result = DocsFetcher::HtmlToMarkdown.convert(html)

    assert_not_empty result[:content]
    assert_equal "Getting Started", result[:title]
    assert_includes result[:headings], "Installation"
  end

  test "returns empty result for empty HTML" do
    result = DocsFetcher::HtmlToMarkdown.convert("<html><body></body></html>")

    assert_nil result[:title]
    assert_equal "", result[:content]
    assert_empty result[:headings]
  end

  # --- Noise stripping ---

  test "strips navigation elements" do
    html = <<~HTML
      <html>
        <body>
          <nav><a href="/">Home</a><a href="/docs">Docs</a></nav>
          <article>
            <h1>Documentation</h1>
            <p>This is the actual content of the documentation page that should be extracted and converted properly.</p>
          </article>
          <footer>Copyright 2024</footer>
        </body>
      </html>
    HTML

    result = DocsFetcher::HtmlToMarkdown.convert(html)

    assert_not_includes result[:content], "Home"
    assert_not_includes result[:content], "Copyright 2024"
    assert_includes result[:content], "actual content"
  end

  test "strips script and style tags" do
    html = <<~HTML
      <html>
        <body>
          <script>var x = 1;</script>
          <style>.foo { color: red; }</style>
          <article>
            <h1>Content Page</h1>
            <p>This is the real content that should appear in the final markdown output after processing.</p>
          </article>
        </body>
      </html>
    HTML

    result = DocsFetcher::HtmlToMarkdown.convert(html)

    assert_not_includes result[:content], "var x = 1"
    assert_not_includes result[:content], "color: red"
    assert_includes result[:content], "real content"
  end

  test "strips sidebar and table of contents" do
    html = <<~HTML
      <html>
        <body>
          <div class="sidebar">Sidebar content that should be removed</div>
          <div class="toc">Table of Contents</div>
          <article>
            <h1>Main Article</h1>
            <p>This is the main article content that should be preserved after stripping sidebar and navigation elements.</p>
          </article>
        </body>
      </html>
    HTML

    result = DocsFetcher::HtmlToMarkdown.convert(html)

    assert_not_includes result[:content], "Sidebar content"
    assert_not_includes result[:content], "Table of Contents"
    assert_includes result[:content], "main article content"
  end

  # --- Content extraction ---

  test "prefers article tag for content" do
    html = <<~HTML
      <html>
        <body>
          <div id="app">
            <div class="header">Header noise that should not appear in output</div>
            <article>
              <h1>Article Content</h1>
              <p>The actual documentation content lives inside the article tag and should be extracted properly.</p>
            </article>
            <div class="footer">Footer noise</div>
          </div>
        </body>
      </html>
    HTML

    result = DocsFetcher::HtmlToMarkdown.convert(html)

    assert_includes result[:content], "documentation content"
  end

  test "falls back to main tag" do
    html = <<~HTML
      <html>
        <body>
          <main>
            <h1>Main Content</h1>
            <p>This content is inside the main tag and should be extracted when no article tag is found in the HTML.</p>
          </main>
        </body>
      </html>
    HTML

    result = DocsFetcher::HtmlToMarkdown.convert(html)

    assert_includes result[:content], "inside the main tag"
  end

  test "falls back to role=main" do
    html = <<~HTML
      <html>
        <body>
          <div role="main">
            <h1>Main Role Content</h1>
            <p>This content uses role=main attribute and should be found by the content selector fallback mechanism properly.</p>
          </div>
        </body>
      </html>
    HTML

    result = DocsFetcher::HtmlToMarkdown.convert(html)

    assert_includes result[:content], "role=main attribute"
  end

  test "falls back to body when no content selectors match" do
    html = <<~HTML
      <html>
        <body>
          <h1>Body Content</h1>
          <p>There are no semantic content containers here so the converter should fall back to using the body tag for extraction.</p>
        </body>
      </html>
    HTML

    result = DocsFetcher::HtmlToMarkdown.convert(html)

    assert_includes result[:content], "no semantic content"
  end

  # --- Title extraction ---

  test "extracts title from h1" do
    html = <<~HTML
      <html>
        <head><title>Page Title - Site Name</title></head>
        <body>
          <article>
            <h1>H1 Title</h1>
            <p>Content that is long enough to pass the minimum length threshold for the content detection algorithm to work.</p>
          </article>
        </body>
      </html>
    HTML

    result = DocsFetcher::HtmlToMarkdown.convert(html)
    assert_equal "H1 Title", result[:title]
  end

  test "falls back to title tag when no h1" do
    html = <<~HTML
      <html>
        <head><title>Documentation - My Library</title></head>
        <body>
          <article>
            <p>This content has no H1 heading so the title extractor should fall back to using the HTML title tag content instead.</p>
          </article>
        </body>
      </html>
    HTML

    result = DocsFetcher::HtmlToMarkdown.convert(html)
    assert_equal "Documentation", result[:title]
  end

  # --- Heading extraction ---

  test "extracts H2-H4 headings from markdown" do
    html = <<~HTML
      <html>
        <body>
          <article>
            <h1>Title</h1>
            <p>Introductory paragraph with enough text to satisfy the minimum content length threshold for detection.</p>
            <h2>Section One</h2>
            <p>Content for section one.</p>
            <h3>Subsection</h3>
            <p>Content for subsection.</p>
            <h4>Deep Section</h4>
            <p>Content for deep section.</p>
          </article>
        </body>
      </html>
    HTML

    result = DocsFetcher::HtmlToMarkdown.convert(html)

    assert_includes result[:headings], "Section One"
    assert_includes result[:headings], "Subsection"
    assert_includes result[:headings], "Deep Section"
  end

  # --- Markdown cleanup ---

  test "collapses excessive blank lines" do
    converter = DocsFetcher::HtmlToMarkdown.new("<html><body></body></html>")
    cleaned = converter.send(:clean_markdown, "Line 1\n\n\n\n\nLine 2")
    assert_equal "Line 1\n\nLine 2", cleaned
  end

  test "removes links with empty href" do
    converter = DocsFetcher::HtmlToMarkdown.new("<html><body></body></html>")
    cleaned = converter.send(:clean_markdown, "Click [here]() for info")
    assert_equal "Click here for info", cleaned
  end

  test "removes clearly decorative images" do
    html = <<~HTML
      <html>
        <body>
          <article>
            <img src="data:image/svg+xml,abc" alt="">
            <img src="https://cdn.example.com/icon.png" alt="" width="24" height="24">
            <p>This is the actual content that should remain after decorative images are stripped from the page.</p>
          </article>
        </body>
      </html>
    HTML

    result = DocsFetcher::HtmlToMarkdown.convert(html)

    assert_includes result[:content], "actual content"
    assert_not_includes result[:content], "data:image/svg+xml"
    assert_not_includes result[:content], "cdn.example.com/icon.png"
    refute_match(/\[\s*\]\(/, result[:content])
  end

  test "preserves large and linked content images even when alt text is empty" do
    html = <<~HTML
      <html>
        <body>
          <article>
            <img src="https://cdn.example.com/hero.png" alt="" width="640" height="480">
            <a href="https://example.com/fullsize">
              <img src="https://cdn.example.com/linked.png" alt="" width="48" height="48">
            </a>
            <p>This page includes meaningful media that should remain in markdown output.</p>
          </article>
        </body>
      </html>
    HTML

    result = DocsFetcher::HtmlToMarkdown.convert(html)

    assert_includes result[:content], "![](https://cdn.example.com/hero.png)"
    assert_match(/\[!\[\]\(https:\/\/cdn\.example\.com\/linked\.png\)\s*\]\(https:\/\/example\.com\/fullsize\)/, result[:content])
  end

  test "converts iframe and video embeds into markdown links" do
    html = <<~HTML
      <html>
        <body>
          <article>
            <iframe src="https://www.youtube.com/embed/demo123"></iframe>
            <video controls>
              <source src="https://cdn.example.com/demo.mp4" type="video/mp4">
            </video>
            <p>This page contains embedded media that should degrade into links.</p>
          </article>
        </body>
      </html>
    HTML

    result = DocsFetcher::HtmlToMarkdown.convert(html)

    assert_includes result[:content], "[YouTube video](https://www.youtube.com/embed/demo123)"
    assert_includes result[:content], "[Video](https://cdn.example.com/demo.mp4)"
  end

  test "unwraps facebook redirect links and strips tracking query params" do
    html = <<~HTML
      <html>
        <body>
          <article>
            <p>
              Visit
              <a href="https://l.facebook.com/l.php?u=https%3A%2F%2Fturnedninja.com%2Fpricing%3Futm_source%3Dfacebook%26ref%3Dpage_internal&h=abc123&__tn__=%2CO%2CP-R">
                turnedninja.com
              </a>
              for more information about the service and documentation.
            </p>
          </article>
        </body>
      </html>
    HTML

    result = DocsFetcher::HtmlToMarkdown.convert(html)

    assert_includes result[:content], "[turnedninja.com](https://turnedninja.com/pricing)"
    assert_not_includes result[:content], "l.facebook.com"
    assert_not_includes result[:content], "utm_source"
    assert_not_includes result[:content], "__tn__"
  end

  test "normalizes non-breaking spaces in markdown output" do
    html = <<~HTML
      <html>
        <body>
          <article>
            <h1>Title&nbsp;</h1>
            <p>&nbsp;We turn you into your favorite character&nbsp;and make fan arts.</p>
          </article>
        </body>
      </html>
    HTML

    result = DocsFetcher::HtmlToMarkdown.convert(html)

    assert_equal "Title", result[:title]
    assert_includes result[:content], "We turn you into your favorite character and make fan arts."
    assert_not_includes result[:content], "&nbsp;"
    assert_not_includes result[:content], "\u00A0"
  end

  test "unwraps nested pre blocks into a single fenced code block" do
    html = <<~HTML
      <html>
        <body>
          <main>
            <h1>Example</h1>
            <pre>
              <pre>
                <code class="language-yaml">lowdefy: 4.7.2

auth:
  authPages:
    signIn: /login</code>
              </pre>
            </pre>
          </main>
        </body>
      </html>
    HTML

    result = DocsFetcher::HtmlToMarkdown.convert(html)

    assert_includes result[:content], "```yaml"
    assert_includes result[:content], "lowdefy: 4.7.2"
    assert_includes result[:content], "authPages:"
    assert_equal 1, result[:content].scan(/^```yaml$/).size
    assert_equal 1, result[:content].scan(/^```$/).size
    assert_not_includes result[:content], "```\n```"
  end

  test "flattens syntax highlighted code spans inside pre code blocks" do
    html = <<~HTML
      <html>
        <body>
          <main>
            <h1>Example</h1>
            <pre>
              <code class="language-yaml" style="color: red">
                <span>lowdefy:</span><span> </span><span>4.7.2</span>
                <span>
</span><span>auth:</span>
              </code>
            </pre>
          </main>
        </body>
      </html>
    HTML

    result = DocsFetcher::HtmlToMarkdown.convert(html)

    assert_includes result[:content], "```yaml"
    assert_includes result[:content], "lowdefy: 4.7.2"
    assert_includes result[:content], "auth:"
    assert_equal 1, result[:content].scan(/^```yaml$/).size
    assert_equal 1, result[:content].scan(/^```$/).size
    assert_not_includes result[:content], "<span>"
  end

  test "preserves language from lang class aliases on code blocks" do
    html = <<~HTML
      <html>
        <body>
          <main>
            <h1>Example</h1>
            <pre><code class="lang-bash">echo hi</code></pre>
          </main>
        </body>
      </html>
    HTML

    result = DocsFetcher::HtmlToMarkdown.convert(html)

    assert_includes result[:content], "```bash"
    assert_includes result[:content], "echo hi"
  end
end
