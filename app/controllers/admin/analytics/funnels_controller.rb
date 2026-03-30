# frozen_string_literal: true

module Admin
  module Analytics
    class FunnelsController < BaseController
      include FunnelScoped

      def create
        funnel = ::Analytics::Funnel.new(funnel_params)
        funnel.created_by_id = Current.identity&.id

        if funnel.save
          render json: camelize_keys({ funnel: { name: funnel.name, steps: funnel.steps } }), status: :created
        else
          render json: { error: funnel.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      def update
        @funnel.assign_attributes(update_funnel_params)

        if @funnel.save
          render json: camelize_keys({ funnel: { name: @funnel.name, steps: @funnel.steps } })
        else
          render json: { error: @funnel.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      def destroy
        @funnel.destroy
        head :no_content
      end

      private
        def funnel_params
          raw = params.require(:funnel).to_unsafe_h.slice("name", "steps").with_indifferent_access
          raw[:steps] = normalize_steps(raw[:steps])
          raw
        end

        def update_funnel_params
          raw = params.require(:funnel).to_unsafe_h.slice("name", "steps").with_indifferent_access.compact
          raw[:steps] = normalize_steps(raw[:steps]) if raw.key?(:steps)
          raw
        end

        def normalize_steps(steps)
          ::Analytics::Funnel.normalize_steps(steps)
        end
    end
  end
end
