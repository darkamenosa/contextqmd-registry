# frozen_string_literal: true

module Analytics::Pagination
  class << self
    def paginate_names(names, limit:, page:)
      offset = (page - 1) * limit
      window = names.slice(offset, limit + 1) || []
      [ window.first(limit), window.length > limit ]
    end

    def list_response(results:, metrics:, has_more: false, skip_imported_reason: nil, metric_labels: nil)
      base = { results: results, metrics: metrics, meta: { has_more: has_more, skip_imported_reason: skip_imported_reason } }
      base[:meta][:metric_labels] = metric_labels if metric_labels
      base
    end
  end
end
