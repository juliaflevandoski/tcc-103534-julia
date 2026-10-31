class CreateClassPostComments < ActiveRecord::Migration[8.1]
  def change
    create_table :class_post_comments do |t|
      t.references :class_post, null: false, foreign_key: true
      t.references :author, null: false, polymorphic: true
      t.text :body, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :class_post_comments, [ :class_post_id, :created_at ], name: "index_class_post_comments_on_post_and_created_at"
  end
end
