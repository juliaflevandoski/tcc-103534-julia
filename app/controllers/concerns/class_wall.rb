module ClassWall
  extend ActiveSupport::Concern

  private

  def set_school_class
    @school_class = SchoolClass.active.find(params[:school_class_id])
  end

  def load_wall
    authorize ClassPost.new(school_class: @school_class), :index?
    @posts = @school_class.class_posts.active.recent_first.includes(:teacher).to_a
    @comments_by_post = ClassPostComment.active.where(class_post_id: @posts.map(&:id)).chronological
                                        .includes(:author).group_by(&:class_post_id)
    @new_post ||= @school_class.class_posts.build
  end
end
