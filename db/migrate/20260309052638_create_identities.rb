# frozen_string_literal: true

class CreateIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :identities do |t|
      ## Database authenticatable
      t.string :email, null: false, default: ""
      t.string :encrypted_password, null: false, default: ""

      ## Recoverable
      t.string :reset_password_token
      t.datetime :reset_password_sent_at

      ## Rememberable
      t.datetime :remember_created_at

      ## Trackable
      t.integer :sign_in_count, null: false, default: 0
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at
      t.string :current_sign_in_ip
      t.string :last_sign_in_ip

      ## OmniAuth
      t.string :provider
      t.string :uid

      ## Custom
      t.boolean :password_set_by_user, null: false, default: false
      t.boolean :staff, null: false, default: false
      t.datetime :suspended_at

      t.timestamps null: false
    end

    add_index :identities, :email, unique: true
    add_index :identities, :reset_password_token, unique: true
    add_index :identities, [ :provider, :uid ], unique: true
  end
end
