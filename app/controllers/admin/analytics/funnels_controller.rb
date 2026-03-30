# frozen_string_literal: true

module Admin
  module Analytics
    class FunnelsController < BaseController
      def create
        funnel = ::Analytics::Funnel.new(funnel_params)
        funnel.analytics_site ||= ::Analytics::Current.site if ::Analytics::Current.site.present?
        funnel.created_by_id = Current.identity&.id

        if funnel.save
          render json: camelize_keys({ funnel: { name: funnel.name, steps: funnel.steps } }), status: :created
        else
          render json: { error: funnel.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      def update
        funnel = ::Analytics::Funnel.effective_find_by_name(params[:id]) || raise(ActiveRecord::RecordNotFound)
        funnel.assign_attributes(update_funnel_params)

        if funnel.save
          render json: camelize_keys({ funnel: { name: funnel.name, steps: funnel.steps } })
        else
          render json: { error: funnel.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      def destroy
        funnel = ::Analytics::Funnel.effective_find_by_name(params[:id]) || raise(ActiveRecord::RecordNotFound)
        funnel.destroy
        head :no_content
      end

      private
        def funnel_params
          raw = params.expect(funnel: [ :name, steps: [] ])
          raw[:steps] = normalize_steps(raw[:steps])
          raw
        end

        def update_funnel_params
          raw = params.expect(funnel: [ :name, steps: [] ]).compact
          raw[:steps] = normalize_steps(raw[:steps]) if raw.key?(:steps)
          raw
        end

        def normalize_steps(steps)
          Array(steps).map { |s| s.is_a?(Hash) ? s : { "label" => s.to_s } }
        end
    end
  end
end
