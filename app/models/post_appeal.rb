class PostAppeal < ApplicationRecord
  class Error < StandardError; end

  MAX_APPEALS_PER_DAY = 1

  belongs_to :creator, :class_name => "User"
  belongs_to :post

  validates :reason, presence: true, length: { in: 1..140 }
  validate :validate_post_is_appealable, on: :create
  validate :validate_creator_is_not_limited, on: :create
  validates :creator, uniqueness: { scope: :post, message: "have already appealed this post" }, on: :create

  enum status: {
    pending: 0,
    succeeded: 1,
    rejected: 2
  }

  scope :resolved, -> { where(post: Post.undeleted.unflagged) }
  scope :unresolved, -> { where(post: Post.deleted.or(Post.flagged)) }
  scope :recent, -> { where("post_appeals.created_at >= ?", 1.day.ago) }
  scope :expired, -> { pending.where("post_appeals.created_at <= ?", 3.days.ago) }

  module SearchMethods
    def search(params)
      q = super
      q = q.search_attributes(params, :creator, :post, :reason, :status)
      q = q.text_attribute_matches(:reason, params[:reason_matches])

      q = q.resolved if params[:is_resolved].to_s.truthy?
      q = q.unresolved if params[:is_resolved].to_s.falsy?

      q.apply_default_order(params)
    end
  end

  extend SearchMethods

  def resolved?
    post.present? && !post.is_deleted? && !post.is_flagged?
  end

  def is_resolved
    resolved?
  end

  def validate_creator_is_not_limited
    if appeal_count_for_creator >= MAX_APPEALS_PER_DAY
      errors[:creator] << "can appeal at most #{MAX_APPEALS_PER_DAY} post a day"
    end
  end

  def validate_post_is_appealable
    errors[:post] << "cannot be appealed" if post.is_status_locked? || !post.is_appealable?
  end

  def appeal_count_for_creator
    creator.post_appeals.recent.count
  end

  def self.available_includes
    [:creator, :post]
  end
end
