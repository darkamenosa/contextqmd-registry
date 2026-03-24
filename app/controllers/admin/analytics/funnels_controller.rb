# frozen_string_literal: true

module Admin
  module Analytics
    class FunnelsController < BaseController
      def create
        funnel = Funnel.new(funnel_params)
        funnel.created_by_id = Current.identity&.id

        if funnel.save
          render json: camelize_keys({ funnel: { name: funnel.name, steps: funnel.steps } }), status: :created
        else
          render json: { error: funnel.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      def update
        funnel = Funnel.find_by!(name: params[:id])
        funnel.assign_attributes(update_funnel_params)

        if funnel.save
          render json: camelize_keys({ funnel: { name: funnel.name, steps: funnel.steps } })
        else
          render json: { error: funnel.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      def destroy
        funnel = Funnel.find_by!(name: params[:id])
        funnel.destroy
        head :no_content
      end

      private
        def funnel_params
          params.expect(funnel: [ :name, steps: [] ])
        end

        def update_funnel_params
          params.expect(funnel: [ :name, steps: [] ]).compact
        end
    end
  end
end
