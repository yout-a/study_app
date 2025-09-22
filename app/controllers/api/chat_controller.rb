class Api::ChatController < ApplicationController
  protect_from_forgery with: :exception
  skip_before_action :verify_authenticity_token, only: :suggest_word, if: -> { request.format.json? }
  before_action :authenticate_user!

  def suggest_word
    term = params[:term].to_s.strip
    memo = params[:memo].to_s.strip
    tags = parse_tags(params[:tags])

    if term.blank?
      render json: { error: "term is required" }, status: :unprocessable_entity and return
    end

    # ▼ ここを統一：OpenAI直叩き＆独自system_promptは廃止
    result = MeaningFinder.call(word: term, memo: memo, tags: tags)

    if result[:meaning].present?
      # meaning / tags / 参照元URL（sources）も返す
      render json: result.slice(:meaning, :tags, :sources, :fallback), status: :ok
    else
      render json: { error: "AIから有効な文章を取得できませんでした。" }, status: :bad_gateway
    end
  rescue => e
    Rails.logger.error("[ChatController#suggest_word] #{e.class}: #{e.message}")
    render json: { error: "生成に失敗しました。時間をおいて再度お試しください。" }, status: :bad_gateway
  end

  private

  def parse_tags(raw)
    return [] if raw.blank?
    raw.to_s.tr("　", " ")
       .gsub(/[、，;]/, ",")
       .split(/[,\s]+/)
       .map(&:strip)
       .reject(&:blank?)
       .first(10)
  end
end
