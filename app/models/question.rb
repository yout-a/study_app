class Question < ApplicationRecord
  belongs_to :word
  has_many :question_choices, dependent: :destroy, inverse_of: :question
end
