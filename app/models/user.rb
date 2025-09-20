class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable,
         :rememberable, :validatable

  has_many :words,  dependent: :destroy
  has_many :tests,  dependent: :destroy   

  def dashboard_stats
    rel = tests.where(status: :finished)
    {
      tests_count: rel.count,
      avg_accuracy: (rel.any? ? (rel.map(&:accuracy).sum / rel.size.to_f).round : 0),
      last_test_at: rel.maximum(:finished_at)
    }
  end
end
