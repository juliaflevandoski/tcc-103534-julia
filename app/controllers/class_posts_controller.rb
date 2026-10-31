class ClassPostsController < ApplicationController
  include ClassWall

  before_action :set_school_class
  before_action :set_class_post, only: %i[edit update destroy]

  def index
    load_wall
  end

  def create
    @new_post = @school_class.class_posts.build(class_post_params)
    authorize @new_post
    return redirect_to school_class_class_posts_path(@school_class), notice: "Publicação criada." if @new_post.save

    load_wall
    render :index, status: :unprocessable_entity
  end

  def edit
    authorize @class_post
  end

  def update
    authorize @class_post
    return redirect_to school_class_class_posts_path(@school_class), notice: "Publicação atualizada." if @class_post.update(class_post_params)

    render :edit, status: :unprocessable_entity
  end

  def destroy
    authorize @class_post
    @class_post.update!(active: false)
    redirect_to school_class_class_posts_path(@school_class), notice: "Publicação excluída."
  end

  private

  def set_class_post
    @class_post = @school_class.class_posts.active.find(params[:id])
  end

  def class_post_params
    params.require(:class_post).permit(:body)
  end
end
