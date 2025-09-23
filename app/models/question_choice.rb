class QuestionChoice < ApplicationRecord
  belongs_to :question
  validates :body, presence: true

  def display_text
    %i[body text content label title].each do |attr|
      return public_send(attr) if respond_to?(attr) && public_send(attr).present?
    end
    nil
  end
end
