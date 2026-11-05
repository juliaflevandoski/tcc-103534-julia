import { Controller } from "@hotwired/stimulus"

// Atualiza as opções de aula e exercício a partir dos dados autorizados embutidos na página.
// O servidor continua validando os IDs enviados.
export default class extends Controller {
  static targets = [ "schoolClass", "student", "activity", "exercise" ]
  static values = { options: Object }

  resetActivity() {
    const options = this.optionsValue[this.schoolClassTarget.value] || { students: [], activities: [], exercises: [] }
    this.fill(this.studentTarget, options.students.map((student) => [ student.id, student.label ]), "Todos os alunos")
    this.fill(this.activityTarget, options.activities.map((activity) => [ activity.id, activity.label ]), "Todas as aulas")
    this.resetExercise()
  }

  resetExercise() {
    const options = this.optionsValue[this.schoolClassTarget.value] || { exercises: [] }
    const activityId = this.activityTarget.value
    const exercises = options.exercises.filter((exercise) => activityId === "" || String(exercise.activityId) === activityId)
    this.fill(this.exerciseTarget, exercises.map((exercise) => [ exercise.id, exercise.label ]), "Todos os exercícios")
  }

  fill(select, entries, defaultLabel) {
    select.replaceChildren(new Option(defaultLabel, ""))
    entries.forEach(([ value, label ]) => select.append(new Option(label, value)))
    select.value = ""
  }
}
