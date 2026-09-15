# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_14_000000) do
  create_table "activities", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "class_id", null: false
    t.datetime "created_at", null: false
    t.boolean "published", default: false, null: false
    t.integer "teacher_id", null: false
    t.string "title", limit: 150, null: false
    t.datetime "updated_at", null: false
    t.index ["class_id"], name: "index_activities_on_class_id"
    t.index ["teacher_id"], name: "index_activities_on_teacher_id"
  end

  create_table "activities_exercises", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "activity_id", null: false
    t.datetime "created_at", null: false
    t.integer "exercise_id", null: false
    t.integer "points", null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.index ["activity_id", "position"], name: "index_activities_exercises_on_activity_id_and_position", unique: true
    t.index ["activity_id"], name: "index_activities_exercises_on_activity_id"
    t.index ["exercise_id"], name: "index_activities_exercises_on_exercise_id"
  end

  create_table "classes", force: :cascade do |t|
    t.string "access_code", limit: 20, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "description", limit: 255
    t.string "name", limit: 50, null: false
    t.integer "teacher_id", null: false
    t.datetime "updated_at", null: false
    t.integer "xp_points"
    t.index ["access_code"], name: "index_classes_on_access_code", unique: true
    t.index ["teacher_id"], name: "index_classes_on_teacher_id"
  end

  create_table "classes_students", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "class_id", null: false
    t.datetime "created_at", null: false
    t.integer "student_id", null: false
    t.datetime "updated_at", null: false
    t.index ["class_id"], name: "index_classes_students_on_class_id"
    t.index ["student_id", "class_id"], name: "index_classes_students_on_student_id_and_class_id", unique: true
    t.index ["student_id"], name: "index_classes_students_on_student_id", unique: true
  end

  create_table "exercise_attempts", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "activity_exercise_id", null: false
    t.json "answer", default: {}, null: false
    t.json "correct", default: {}, null: false
    t.datetime "created_at", null: false
    t.integer "score", default: 0, null: false
    t.integer "student_id", null: false
    t.integer "time_spent"
    t.datetime "updated_at", null: false
    t.index ["student_id", "activity_exercise_id"], name: "index_exercise_attempts_on_student_id_and_activity_exercise_id"
    t.index ["student_id"], name: "index_exercise_attempts_on_student_id"
  end

  create_table "exercises", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "description", limit: 255
    t.string "exercise_type", limit: 50, null: false
    t.json "object", default: {}, null: false
    t.integer "teacher_id", null: false
    t.string "title", limit: 150
    t.datetime "updated_at", null: false
    t.index ["teacher_id"], name: "index_exercises_on_teacher_id"
  end

  create_table "student_stats", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "level", default: 1, null: false
    t.integer "student_id", null: false
    t.datetime "updated_at", null: false
    t.integer "xp", default: 0, null: false
    t.index ["student_id"], name: "index_student_stats_on_student_id"
  end

  create_table "students", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "email", limit: 150, null: false
    t.string "name", limit: 150, null: false
    t.string "password_digest", limit: 150, null: false
    t.string "token", limit: 255
    t.datetime "updated_at", null: false
    t.string "username", limit: 50, null: false
    t.index ["email"], name: "index_students_on_email", unique: true
    t.index ["username"], name: "index_students_on_username", unique: true
  end

  create_table "teachers", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "email", limit: 150, null: false
    t.string "name", limit: 150, null: false
    t.string "password_digest", limit: 150, null: false
    t.string "token", limit: 255
    t.datetime "updated_at", null: false
    t.string "username", limit: 50, null: false
    t.index ["email"], name: "index_teachers_on_email", unique: true
    t.index ["username"], name: "index_teachers_on_username", unique: true
  end

  add_foreign_key "activities", "classes"
  add_foreign_key "activities", "teachers"
  add_foreign_key "activities_exercises", "activities"
  add_foreign_key "activities_exercises", "exercises"
  add_foreign_key "classes", "teachers"
  add_foreign_key "classes_students", "classes"
  add_foreign_key "classes_students", "students"
  add_foreign_key "exercise_attempts", "students"
  add_foreign_key "exercises", "teachers"
  add_foreign_key "student_stats", "students"
end
