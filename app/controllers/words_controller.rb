# app/controllers/words_controller.rb
class WordsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_word, only: %i[edit update destroy]

  def index
    @q     = params[:q].to_s.strip
    @page  = [params[:page].to_i, 1].max
    per    = 20

    base = current_user.words
                       .left_joins(:tags)
                       .distinct

    if @q.present?
      # % と _ をエスケープして安全に LIKE 検索
      needle = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
      base = base.where(
        "words.term    LIKE :needle OR " \
        "words.meaning LIKE :needle OR " \
        "tags.name     LIKE :needle",
        needle: needle
      )
      # 大文字小文字を区別したいなら ↑ を LOWER(...) に置換して両辺LOWER比較に
      # 例）LOWER(words.term) LIKE LOWER(:needle)
    end

    @total = base.count
    @words = base.order(updated_at: :desc)
                 .offset((@page - 1) * per)
                 .limit(per)
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
