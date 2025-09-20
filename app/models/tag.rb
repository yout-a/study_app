# app/models/tag.rb
class Tag < ApplicationRecord
  has_many :word_taggings, dependent: :destroy
  has_many :words, through: :word_taggings
  validates :name, presence: true, uniqueness: true, length: { maximum: 50 }
end

