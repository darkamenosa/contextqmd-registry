# frozen_string_literal: true

module Api
  module V1
    module Concerns
      module CursorPaginatable
        extend ActiveSupport::Concern

        private

          DEFAULT_PER_PAGE = 20
          MAX_PER_PAGE = 100

          def paginate(scope, per_page: nil)
            per_page = resolve_per_page(per_page)
            scope = scope.where("#{scope.table_name}.id > ?", decode_cursor) if params[:cursor].present?

            records = scope.order("#{scope.table_name}.id ASC").limit(per_page + 1).to_a

            if records.size > per_page
              records.pop
              next_cursor = encode_cursor(records.last.id)
            end

            { records: records, next_cursor: next_cursor }
          end

          def resolve_per_page(override)
            if override
              override.clamp(1, MAX_PER_PAGE)
            elsif params[:per_page].present?
              params[:per_page].to_i.clamp(1, MAX_PER_PAGE)
            else
              DEFAULT_PER_PAGE
            end
          end

          def decode_cursor
            Base64.urlsafe_decode64(params[:cursor]).to_i
          rescue ArgumentError
            0
          end

          def encode_cursor(id)
            Base64.urlsafe_encode64(id.to_s, padding: false)
          end
      end
    end
  end
end
