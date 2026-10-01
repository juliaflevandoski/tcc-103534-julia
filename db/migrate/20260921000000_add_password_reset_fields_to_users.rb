class AddPasswordResetFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :teachers, bulk: true do |t|
      t.string :password_reset_token, limit: 255
      t.datetime :password_reset_sent_at
    end

    change_table :students, bulk: true do |t|
      t.string :password_reset_token, limit: 255
      t.datetime :password_reset_sent_at
    end

    add_index :teachers, :password_reset_token, unique: true
    add_index :students, :password_reset_token, unique: true
  end
end
