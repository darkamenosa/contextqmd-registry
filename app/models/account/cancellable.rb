# frozen_string_literal: true

module Account::Cancellable
  extend ActiveSupport::Concern

  included do
    has_one :cancellation, class_name: "Account::Cancellation", dependent: :destroy

    define_callbacks :cancel, :reactivate
  end

  def cancel(initiated_by: Current.user)
    with_lock do
      if active?
        run_callbacks :cancel do
          create_cancellation!(initiated_by: initiated_by)
        end
      end
    end
  end

  def reactivate
    with_lock do
      if cancelled?
        run_callbacks :reactivate do
          cancellation.destroy
          reload_cancellation
        end
      end
    end
  end

  def cancelled?
    cancellation.present?
  end
end
