# frozen_string_literal: true

# Inject account associations into Rails framework models.
# Follows fizzy (37signals) pattern: framework models get `belongs_to :account`
# so files are owned by the tenant and cascade-deleted on account incineration.
#
# Prerequisites (when ActiveStorage is installed):
#   1. bin/rails active_storage:install
#   2. Migration to add account_id to active_storage_blobs, active_storage_attachments,
#      and active_storage_variant_records
#   3. bin/rails db:migrate
Rails.application.config.to_prepare do
  ActiveStorage::Attachment.belongs_to :account, default: -> { record.account }

  ActiveStorage::Blob.belongs_to :account, default: -> { Current.account }

  ActiveStorage::VariantRecord.belongs_to :account, default: -> { blob.account }
end
