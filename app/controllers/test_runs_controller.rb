class TestRunsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_test
  before_action :set_tq, only: [:show, :answer]

  def show
    @question = @tq.question
    @answer   = Answer.find_or_initialize_by(test: @test, question: @question, user: current_user)

    rand_sql = ActiveRecord::Base.connection.adapter_name.match?(/mysql/i) ? 'RAND()' : 'RANDOM()'
    @choices = @question.question_choices.order(Arel.sql(rand_sql))  # ← ランダム表示
    @mode_multiple = @test.multiple?
  end

  def answer
    @question = @tq.question

    Answer.transaction do
      answer = Answer.find_or_initialize_by(test: @test, question: @question, user: current_user)
      answer.answer_selections.destroy_all

      choice_ids = Array(params[:choice_ids]).map(&:to_i).uniq
      choice_ids.each { |cid| answer.answer_selections.build(question_choice_id: cid) }
      answer.save!
      answer.grade!
    end

    next_pos = @tq.position + 1
    if next_pos <= @test.test_questions.maximum(:position)
      redirect_to question_test_path(@test, pos: next_pos)
    else
      @test.update!(status: :finished, finished_at: Time.current)
      redirect_to result_test_path(@test), notice: "テストを終了しました"   # ← 結果へ
    end
  end
  private

  def set_test
    @test = current_user.tests.find(params[:id])
  end

  def set_tq
    @tq = @test.test_questions.includes(question: :question_choices)
              .find_by!(position: params[:pos].to_i)
  end
end
