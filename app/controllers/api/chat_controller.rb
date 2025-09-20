# app/controllers/api/chat_controller.rb
class Api::ChatController < ApplicationController
  protect_from_forgery with: :exception
  skip_before_action :verify_authenticity_token, only: :suggest_word

  def suggest_word
    term  = params[:term].to_s.strip
    memo  = params[:memo].to_s.strip
    exist = params[:existing_meaning].to_s.strip

    if term.blank?
      render json: { error: "term is required" }, status: :unprocessable_entity and return
    end

    client = OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY"))

    system_prompt = <<~SYS
      あなたは辞書の作成を手伝うアシスタントです。
      WEB上から、情報を集めてください。
      更新の際に"word_memo"の情報も足して情報をアップグレードしてください
      以下のフォーマットの JSON だけを返してください：
      {
        "meaning": "単語の情報を日本語で1,000文字以内でまとめてください。",
        "tags": ["API","Security"]  # カンマ区切りのタグ、日本語で表示、最大5個
      }
    SYS

    user_prompt = <<~USR
      単語: #{term}
      既存の意味: #{exist.presence || "なし"}
      補足メモ: #{memo.presence || "なし"}
    USR

    begin
      resp = client.chat(
        parameters: {
          model: "gpt-4o-mini",
          messages: [
            { role: "system", content: system_prompt },
            { role: "user",   content: user_prompt }
          ],
          temperature: 0.3
        }
      )

      # ★ 修正ポイント：レスポンスの掘り方
      raw  = resp.dig("choices", 0, "message", "content")
      data = JSON.parse(raw) rescue nil

      if data.is_a?(Hash) && data["meaning"].present?
        tags = Array(data["tags"]).map(&:to_s).reject(&:blank?)
        render json: { meaning: data["meaning"].to_s, tags: tags }, status: :ok
      else
        render json: { error: "LLMから有効なJSONを受け取れませんでした。" }, status: :bad_gateway
      end
    rescue => e
      Rails.logger.error("[OpenAI] #{e.class} #{e.message}")
      render json: { error: "生成に失敗しました。時間をおいて再度お試しください。" }, status: :bad_gateway
    end
  end
end

