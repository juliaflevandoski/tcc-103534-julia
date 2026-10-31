class CreateClassPosts < ActiveRecord::Migration[8.1]
  def change
    create_table :class_posts do |t|
      t.integer :class_id, null: false
      t.references :teacher, null: false, foreign_key: true
      t.text :body, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :class_posts, [ :class_id, :created_at ]
    add_foreign_key :class_posts, :classes, column: :class_id
  end
end
