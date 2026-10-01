class AllowStudentsInMultipleClasses < ActiveRecord::Migration[8.1]
  def change
    remove_index :classes_students, :student_id
    add_index :classes_students, :student_id
  end
end
