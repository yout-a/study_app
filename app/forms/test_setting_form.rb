# app/forms/test_setting_form.rb
class TestSettingForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :tag_id, :integer
  attribute :only_unlearned, :boolean, default: true
  attribute :question_count, :integer, default: 10
  attribute :question_type, :string,  default: "single" # "single" / "multiple"
  attribute :grading, :string,       default: "batch"   # "batch" / "instant"

  validates :question_count, inclusion: { in: [5,10,20,30,50] }, allow_nil: true

  def to_h
    {
      tag_id: tag_id.presence,
      only_unlearned: ActiveModel::Type::Boolean.new.cast(only_unlearned),
      question_count: (question_count.presence || 10).to_i,
      question_type: question_type,
      grading: grading
    }
  end
end
