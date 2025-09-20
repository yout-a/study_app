# app/controllers/tests_controller.rb
class TestsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_test, only: [:show, :start, :result]

  def new
    @test = current_user.tests.new(
      scope: :unlearned, item_count: 10, mode: :single, grading: :batch
    )
  end

  def create
    @test = current_user.tests.new(test_params.merge(status: :scheduled))
    if @test.save && Tests::BuildQuestions.new(@test).call
      redirect_to start_test_path(@test), notice: "テストを開始しました"   # ← 直接開始
    else
      flash.now[:alert] = "問題を生成できませんでした"
      render :new, status: :unprocessable_entity
    end
  end

  def show
    # ひとまず設定の確認ページ（のちに実施画面に遷移）
  end

  def start
    # 念のため、問題が無ければ生成（手動実行や別経路で来た時の保険）
    if @test.test_questions.blank?
      Tests::BuildQuestions.new(@test).call
    end

    first_pos = @test.test_questions.minimum(:position)
    if first_pos.present?
      redirect_to question_test_path(@test, pos: first_pos)
    else
      redirect_to @test, alert: "問題が見つかりませんでした。出題設定を確認してください。"
    end
  end

  def result
    @total    = @test.test_questions.count
    @answers  = @test.answers.includes(:question, :question_choices)
    @corrects = @answers.where(correct: true).count
    @rate     = (@total.zero? ? 0 : (@corrects * 100.0 / @total)).round
    @wrongs   = @answers.where(correct: false)
  end

  private

  def set_test
    @test = current_user.tests.find(params[:id])
  end

  def test_params
    params.require(:test).permit(:scope, :item_count, :mode, :grading)
  end
end
