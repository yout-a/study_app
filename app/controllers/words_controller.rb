# app/controllers/words_controller.rb
class WordsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_word, only: %i[edit update destroy]

  protect_from_forgery with: :exception

  def index
    @q    = params[:q].to_s.strip
    @page = [params[:page].to_i, 1].max
    per   = 20

    base = current_user.words.left_joins(:tags).distinct
    if @q.present?
      needle = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
      base = base.where(
        "words.term LIKE :needle OR words.meaning LIKE :needle OR tags.name LIKE :needle",
        needle: needle
      )
    end

    @total = base.count
    @words = base.order(updated_at: :desc).offset((@page - 1) * per).limit(per)
  end

  def new
    @word = current_user.words.new
  end

  def create
    @word = current_user.words.new(word_params)
    if @word.save
      redirect_to words_path, notice: "単語を登録しました"
    else
      flash.now[:alert] = "入力内容を確認してください"
      render :new, status: :unprocessable_entity
    end
  end

  def ai_suggest
    word = params[:word].to_s.strip
    memo = params[:memo].to_s.strip
    return render json: { error: "単語（word）を入力してください" }, status: :unprocessable_entity if word.blank?

    # ここで外部検索。失敗しても例外を外へ出さない実装にしてある
    result = MeaningFinder.call(word: word, memo: memo)

    meaning = result[:meaning].presence || MeaningFinder.offline_fallback(word: word, memo: memo)
    tags    = Array(result[:tags]).presence || SmartTagger.call(text: meaning, word: word, memo_keywords: MeaningFinder.send(:build_keywords, word, memo), limit: 5)

    render json: {
      meaning: meaning,
      tags: tags.first(5),
      sources: result[:sources] || [],
      fallback: result[:fallback] || false
    }
  rescue => e
    Rails.logger.error("[ai_suggest] #{e.class}: #{e.message}\n#{e.backtrace&.first}")
    # どんな例外でも必ず正常レスポンスで返す（UX優先）
    meaning = MeaningFinder.offline_fallback(word: word, memo: memo)
    tags    = SmartTagger.call(text: meaning, word: word, memo_keywords: MeaningFinder.send(:build_keywords, word, memo), limit: 5)
    render json: { meaning: meaning, tags: tags, sources: [], fallback: true, error_detail: e.message }
  end

  def edit; end

  def update
    if @word.update(word_params)
      redirect_to words_path, notice: "単語を更新しました"
    else
      flash.now[:alert] = "入力内容を確認してください"
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @word.destroy
    redirect_to words_path, notice: "単語を削除しました"
  end

  private
  def set_word
    @word = current_user.words.find(params[:id])
  end

  def word_params
    params.require(:word).permit(:term, :meaning, :memo, :tags_string)
  end
end

