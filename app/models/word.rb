# app/models/word.rb
class Word < ApplicationRecord
  belongs_to :user
  has_many :word_taggings, dependent: :destroy, inverse_of: :word
  has_many :tags, through: :word_taggings

  validates :term, presence: true, length: { maximum: 255 }
  validates :meaning, presence: true

  # カンマ区切りで受け取ってTagに保存するためのヘルパ
  def tags_string
    tags.pluck(:name).join(', ')
  end
  def tags_string=(csv)
    names = csv.to_s.split(',').map { _1.strip }.reject(&:blank?).uniq
    self.tags = names.map { |n| Tag.find_or_initialize_by(name: n) }
  end
end

