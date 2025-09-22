class Word < ApplicationRecord
  belongs_to :user

  has_many :word_taggings, dependent: :destroy
  has_many :tags, through: :word_taggings

  validates :term, presence: true, length: { maximum: 255 },
                   uniqueness: { scope: :user_id, case_sensitive: false }
  # validates :meaning, presence: true

  before_validation :normalize_term

  def tags_string
    tags.order(:name).pluck(:name).join(', ')
  end

  def tags_string=(str)
    @pending_tag_names =
      str.to_s.split(/[、,，]/).map(&:strip).reject(&:blank?).uniq
  end

  after_save :apply_pending_tags

  private

  def apply_pending_tags
    return if @pending_tag_names.nil?

    names = @pending_tag_names
    existing   = Tag.where(user_id: user_id, name: names).index_by(&:name)
    tag_records = names.map { |n| existing[n] || Tag.create!(user_id: user_id, name: n) }

    self.tags = tag_records
    @pending_tag_names = nil
  end

  def normalize_term
    self.term = term.to_s.strip
  end
end
