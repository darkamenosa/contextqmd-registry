# frozen_string_literal: true

class CreateAccountCancellations < ActiveRecord::Migration[8.1]
  def change
    create_table :account_cancellations do |t|
      t.references :account,
        null: false,
        index: { unique: true, name: "index_account_cancellations_on_account_id_unique" },
        foreign_key: { on_delete: :cascade }
      t.references :initiated_by, foreign_key: { to_table: :users, on_delete: :nullify }

      t.timestamps null: false
    end
  end
end
