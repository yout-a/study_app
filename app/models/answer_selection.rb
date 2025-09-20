class AnswerSelection < ApplicationRecord
  belongs_to :answer
  belongs_to :question_choice
end
