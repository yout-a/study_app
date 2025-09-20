class DashboardsController < ApplicationController
  before_action :authenticate_user!

  def show
    @user = current_user

    # 直近N件のテスト
    @recent_tests = @user.tests
                        .includes(:test_questions, :answers)
                        .order(finished_at: :desc)
                        .limit(10)

    stats = @user.dashboard_stats
    @tests_count  = stats[:tests_count]
    @avg_accuracy = stats[:avg_accuracy]
    @last_test_at = stats[:last_test_at]
  end
end

