# frozen_string_literal: true

class CreateAccounts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE SEQUENCE accounts_external_account_id_seq
        START WITH 1
        INCREMENT BY 1
        NO MINVALUE
        NO MAXVALUE
        CACHE 1
    SQL

    create_table :accounts do |t|
      t.string :name, null: false
      t.boolean :personal, null: false, default: true
      t.bigint :external_account_id,
        null: false,
        default: -> { "nextval('accounts_external_account_id_seq'::regclass)" }

      t.timestamps null: false
    end

    add_index :accounts, :external_account_id, unique: true
  end

  def down
    drop_table :accounts
    execute "DROP SEQUENCE IF EXISTS accounts_external_account_id_seq"
  end
end
