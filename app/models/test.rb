# app/models/test.rb
class Test < ApplicationRecord
  belongs_to :user

  has_many :test_questions, dependent: :destroy
  has_many :questions, through: :test_questions
  has_many :answers, dependent: :destroy
  has_many :test_taggings, dependent: :destroy
  has_many :tags, through: :test_taggings

  # enum（整数カラム）
  enum scope:   { unlearned: 0, all_words: 1 }, _prefix: :scope           # 出題範囲
  enum mode:    { single: 0, multiple: 1 }          # 出題形式
  enum grading: { batch: 0, immediate: 1 }          # 採点方式
  enum status:  { scheduled: 0, running: 1, finished: 2 }, _prefix: :status

  # === 便利エイリアス（_prefix を気にせず使える短縮版） ===
  def single?    = (mode.to_s == "single")
  def multiple?  = (mode.to_s == "multiple")

  def unlearned? = (scope.to_s == "unlearned")
  def all?       = (scope.to_s == "all_words")

  def finished?  = (status.to_s == "finished")
  def running?   = (status.to_s == "running")
  def scheduled? = (status.to_s == "scheduled")

  validates :item_count, presence: true, inclusion: { in: [5,10,15,20] }
  validates :scope, :mode, :grading, presence: true

  def correct_count
    @correct_count ||= answers.where(correct: true).count
  end

  def accuracy
    total = test_questions.count
    return 0 if total.zero?
    ((correct_count * 100.0) / total).round
  end

  def duration_sec
    return nil unless started_at && finished_at
    (finished_at - started_at).to_i
  end

  def scope_label
    return scope_names if scope_names.present?

    if respond_to?(:tags) && tags.loaded? ? tags.any? : tags.exists?
      (tags.loaded? ? tags.map(&:name) : tags.pluck(:name)).join("、")
    else
      scope == "unlearned" ? "未習得" : "全単語"
    end
  end
end
