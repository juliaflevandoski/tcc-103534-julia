class ScopeActivityExercisePositionsToActiveLinks < ActiveRecord::Migration[8.1]
  def change
    remove_index :activities_exercises, name: "index_activities_exercises_on_activity_id_and_position"
    add_index :activities_exercises, %i[activity_id position], unique: true, where: "active = 1"
  end
end
