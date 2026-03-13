# frozen_string_literal: true

module PageHydrationTestHelper
  def hydrate_pages(version)
    version.pages.order(:id).each do |page|
      content = "# #{page.title}\n\nDocumentation for #{page.page_uid}."
      page.update!(
        description: content,
        bytes: content.bytesize,
        checksum: Digest::SHA256.hexdigest(content)
      )
    end
  end
end
