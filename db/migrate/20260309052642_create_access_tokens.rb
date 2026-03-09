# frozen_string_literal: true

class CreateAccessTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :access_tokens do |t|
      t.references :identity, null: false, foreign_key: true
      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :token_prefix, limit: 8
      t.string :permission, null: false, default: "read"
      t.datetime :last_used_at
      t.datetime :expires_at

      t.timestamps null: false
    end

    add_index :access_tokens, :token_digest, unique: true
  end
end
