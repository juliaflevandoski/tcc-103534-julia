class CreateLudusDomain < ActiveRecord::Migration[8.1]
  def change
    create_table :teachers do |t|
      t.string :username, null: false, limit: 50
      t.string :email, null: false, limit: 150
      t.string :password_digest, null: false, limit: 150
      t.string :name, null: false, limit: 150
      t.string :token, limit: 255
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :teachers, :username, unique: true
    add_index :teachers, :email, unique: true

    create_table :students do |t|
      t.string :username, null: false, limit: 50
      t.string :email, null: false, limit: 150
      t.string :password_digest, null: false, limit: 150
      t.string :name, null: false, limit: 150
      t.string :token, limit: 255
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :students, :username, unique: true
    add_index :students, :email, unique: true

    create_table :classes do |t|
      t.references :teacher, null: false, foreign_key: true
      t.string :name, null: false, limit: 50
      t.string :description, limit: 255
      t.integer :xp_points
      t.string :access_code, null: false, limit: 20
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :classes, :access_code, unique: true

    create_table :classes_students do |t|
      t.references :student, null: false, foreign_key: true, index: { unique: true }
      t.references :class, null: false, foreign_key: true
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :classes_students, %i[student_id class_id], unique: true

    create_table :activities do |t|
      t.references :class, null: false, foreign_key: true
      t.references :teacher, null: false, foreign_key: true
      t.string :title, null: false, limit: 150
      t.boolean :published, null: false, default: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    create_table :exercises do |t|
      t.references :teacher, null: false, foreign_key: true
      t.string :exercise_type, null: false, limit: 50
      t.json :object, null: false, default: {}
      t.string :title, limit: 150
      t.string :description, limit: 255
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    create_table :activities_exercises do |t|
      t.references :exercise, null: false, foreign_key: true
      t.references :activity, null: false, foreign_key: true
      t.integer :position, null: false
      t.integer :points, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :activities_exercises, %i[activity_id position], unique: true

    create_table :exercise_attempts do |t|
      t.references :student, null: false, foreign_key: true
      t.integer :activity_exercise_id, null: false
      t.json :answer, null: false, default: {}
      t.json :correct, null: false, default: {}
      t.integer :score, null: false, default: 0
      t.integer :time_spent
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :exercise_attempts, %i[student_id activity_exercise_id]

    create_table :student_stats do |t|
      t.references :student, null: false, foreign_key: true
      t.integer :xp, null: false, default: 0
      t.integer :level, null: false, default: 1
      t.timestamps
    end
  end
end
