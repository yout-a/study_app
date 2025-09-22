# app/models/word.rb
class Word < ApplicationRecord
  belongs_to :user
  has_many :word_taggings, dependent: :destroy
  has_many :tags, through: :word_taggings

  validates :term, presence: true, length: { maximum: 255 },
                   uniqueness: { scope: :user_id, case_sensitive: false }
  # 意味が必須なら残す。任意なら下行は消してOK
  # validates :meaning, presence: true

  before_validation :normalize_term

  # === ここから仮想フィールド ===
  # フォーム表示用：タグ名をカンマ区切りで返す
  def tags_string
    tags.pluck(:name).join(", ")
  end

  # フォーム入力用：カンマ区切り → 関連tagsを更新
  def tags_string=(csv)
    names = csv.to_s.split(",").map(&:strip).reject(&:blank?).uniq.first(5)
    self.tags = names.map { |n| Tag.find_or_create_by(name: n) }
  end
  # === ここまで ===

  private

  def normalize_term
    self.term = term.to_s.strip
  end
end

