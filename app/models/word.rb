class Word < ApplicationRecord
  belongs_to :user
  has_many :word_taggings, dependent: :destroy
  has_many :tags, through: :word_taggings

  validates :term,    presence: true, length: { maximum: 255 }
  validates :meaning, presence: true

  # ✅ ユーザーごとに term の重複を禁止（大文字小文字を区別しない）
  validates :term, presence: true
  validates :term,
            uniqueness: { scope: :user_id, case_sensitive: false }

  before_validation :normalize_term

  # 既存の tags_string ヘルパはそのままでOK
  def tags_string
    tags.pluck(:name).join(",")
  end

  def tags_string=(csv)
    names = csv.to_s.split(",").map { _1.strip }.reject(&:blank?).uniq
    self.tags = names.map { |n| Tag.find_or_initialize_by(name: n) }
  end

  private

  def normalize_term
    self.term = term.to_s.strip
  end
end
