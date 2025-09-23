class Question < ApplicationRecord
  belongs_to :word
  has_many :question_choices, dependent: :destroy, inverse_of: :question

  def display_text
    %i[content text body title statement prompt].each do |attr|
      return public_send(attr) if respond_to?(attr) && public_send(attr).present?
    end
    # Word が紐づくなら最終手段で単語を出す
    return word.term if respond_to?(:word) && word&.term.present?
    nil
  end
end
