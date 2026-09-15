class StudentStatsController < ApplicationController
  before_action :set_student_stat, only: %i[show edit update destroy]

  def index
    @student_stats = StudentStat.includes(:student).order(:student_id)
  end

  def show; end

  def new
    @student_stat = StudentStat.new
    load_options
  end

  def create
    @student_stat = StudentStat.new(student_stat_params)
    return redirect_to @student_stat if @student_stat.save

    load_options
    render :new, status: :unprocessable_entity
  end

  def edit
    load_options
  end

  def update
    return redirect_to @student_stat if @student_stat.update(student_stat_params)

    load_options
    render :edit, status: :unprocessable_entity
  end

  def destroy
    @student_stat.destroy!
    redirect_to student_stats_path, notice: "Estatística removida."
  end

  private

  def set_student_stat
    @student_stat = StudentStat.find(params[:id])
  end

  def load_options
    @students = Student.active.order(:name)
  end

  def student_stat_params
    params.require(:student_stat).permit(:student_id, :xp, :level)
  end
end
