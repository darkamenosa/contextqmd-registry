# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.references :identity, foreign_key: { on_delete: :nullify }
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :role, null: false, default: "member"
      t.boolean :active, null: false, default: true

      t.timestamps null: false

      t.check_constraint "role::text <> 'system'::text OR identity_id IS NULL",
        name: "users_system_role_requires_no_identity"
    end

    add_index :users,
      [ :identity_id, :account_id ],
      unique: true,
      where: "identity_id IS NOT NULL",
      name: "index_users_on_identity_id_and_account_id"
    add_index :users, [ :account_id, :role ], name: "index_users_on_account_id_and_role"
    add_index :users,
      :account_id,
      unique: true,
      where: "role = 'owner'",
      name: "index_users_on_account_id_where_owner"
    add_index :users,
      :account_id,
      unique: true,
      where: "role = 'system'",
      name: "index_users_on_account_id_where_system"
  end
end
