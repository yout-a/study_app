# app/controllers/api/chat_controller.rb
class Api::ChatController < ApplicationController
  protect_from_forgery with: :exception

  # Rails 7: fetch からの CSRF を通す
  skip_before_action :verify_authenticity_token, only: :suggest_word, if: -> { request.format.json? }
  before_action :authenticate_user!  # ログイン必須にする（任意）

  def suggest_word
    term   = params[:term].to_s.strip
    memo   = params[:memo].to_s.strip
    exist  = params[:existing_meaning].to_s.strip

    if term.blank?
      render json: { error: "term is required" }, status: :unprocessable_entity and return
    end

    # ===== OpenAI 呼び出し =====
    # gem 'ruby-openai' を使う版
    client = OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY"))

    system_prompt = <<~SYS
      あなたは英単語学習を手伝うアシスタントです。
      返答は必ず次の JSON 形式で返してください（日本語）:
      {"meaning":"…","tags":["…","…"]}
      - meaning: 初学者にもわかる 1〜2文
      - tags: カンマ無し、5語以内、英語推奨（例: ["API","Security"]）
      - JSON 以外の文字は一切出力しない
    SYS

    user_prompt = <<~USR
      単語: #{term}
      既存の意味: #{exist.presence || "（なし）"}
      参考メモ: #{memo.presence || "（なし）"}
      辞書のように簡潔に。
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
      raw = resp.dig("choices", 0, "message", "content").to_s
      data = JSON.parse(raw) rescue nil

      if data.is_a?(Hash) && data["meaning"].present?
        tags = Array(data["tags"]).map(&:to_s).reject(&:blank?)
        render json: { meaning: data["meaning"].to_s, tags: tags }, status: :ok
      else
        render json: { error: "LLM から有効な JSON を受け取れませんでした。" }, status: :bad_gateway
      end
    rescue => e
      Rails.logger.error("[OpenAI] #{e.class} #{e.message}")
      render json: { error: "生成に失敗しました。時間をおいて再度お試しください。" }, status: :bad_gateway
    end
  end
end
