class ClassPostCommentsController < ApplicationController
  include ClassWall

  before_action :set_school_class
  before_action :set_class_post
  before_action :set_comment, only: %i[edit update destroy]

  def create
    comment = @class_post.comments.build(comment_params.merge(author: current_user))
    authorize comment
    return redirect_to wall_path, notice: "Comentário publicado." if comment.save

    @invalid_comment = comment
    load_wall
    render "class_posts/index", status: :unprocessable_entity
  end

  def edit
    authorize @comment
  end

  def update
    authorize @comment
    return redirect_to wall_path, notice: "Comentário atualizado." if @comment.update(comment_params)

    render :edit, status: :unprocessable_entity
  end

  def destroy
    authorize @comment
    @comment.update!(active: false)
    redirect_to wall_path, notice: "Comentário excluído."
  end

  private

  def wall_path
    school_class_class_posts_path(@school_class)
  end

  def set_class_post
    @class_post = @school_class.class_posts.active.find(params[:class_post_id])
  end

  def set_comment
    @comment = @class_post.comments.active.find(params[:id])
  end

  def comment_params
    params.require(:class_post_comment).permit(:body)
  end
end
