class Tag < ApplicationRecord
  has_many :taggings, dependent: :destroy
  has_many :words, through: :taggings

  has_many :test_taggings, dependent: :destroy
  has_many :tests, through: :test_taggings
end
