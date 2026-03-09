# frozen_string_literal: true

module Account::Incineratable
  extend ActiveSupport::Concern

  INCINERATION_GRACE_PERIOD = 30.days

  included do
    define_callbacks :incinerate

    scope :due_for_incineration, -> {
      joins(:cancellation)
        .where(account_cancellations: { created_at: ...INCINERATION_GRACE_PERIOD.ago })
    }
  end

  def incinerate
    run_callbacks :incinerate do
      destroy
    end
  end
end
