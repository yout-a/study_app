class Answer < ApplicationRecord
  belongs_to :test
  belongs_to :question
  belongs_to :user
  has_many   :answer_selections, dependent: :destroy
  has_many   :question_choices, through: :answer_selections

  accepts_nested_attributes_for :answer_selections, allow_destroy: true

  def grade!
    # 正解集合と選択集合が一致していれば正解
    correct_ids = question.question_choices.where(correct: true).pluck(:id).sort
    chosen_ids  = question_choices.pluck(:id).sort
    update!(correct: correct_ids == chosen_ids, responded_at: Time.current)
  end
end
