# app/models/word_tagging.rb
class WordTagging < ApplicationRecord
  belongs_to :word
  belongs_to :tag
  validates :word_id, uniqueness: { scope: :tag_id }
end
