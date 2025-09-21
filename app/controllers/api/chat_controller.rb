# app/controllers/api/chat_controller.rb
class Api::ChatController < ApplicationController
  protect_from_forgery with: :exception

  # Rails 7: fetch の CSRF を通す
  skip_before_action :verify_authenticity_token, only: :suggest_word, if: -> { request.format.json? }
  before_action :authenticate_user!

  def suggest_word
    term  = params[:term].to_s.strip
    memo  = params[:memo].to_s.strip

    if term.blank?
      render json: { error: "term is required" }, status: :unprocessable_entity and return
    end

    # 既に登録済みなら 409 を返す
    if current_user.words.exists?(["LOWER(term) = ?", term.downcase])
      render json: { error: "この用語はすでに登録されています。" }, status: :conflict and return
    end

    # Web から意味の下地を取得（見つからなければエラー）
    web_summary = WebSummary.fetch(term, lang: "ja")
    if web_summary.blank?
      render json: { error: "Webから要約を取得できませんでした。" }, status: :bad_gateway and return
    end

    # ==== GPT で要約 + メモ統合 → 500字程度の自然な日本語へ整形 ====
    client = OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY"))

    system_prompt = <<~SYS
      あなたは「個人ナレッジベース用の用語ノート」のアシスタントです。
      入力として与える「Web要約」と「ユーザーメモ」を統合し、
      読み手に分かりやすい自然な日本語の文章（約500字、常体、専門外にも分かる平易さ）にまとめてください。
      ・定義→背景/用途→代表例/注意点 の流れがあると望ましいです。
      ・文章以外の出力は厳禁です（JSONや箇条書き、見出し、コード記法は出力しない）。
    SYS

    user_prompt = <<~USR
      用語: #{term}

      Web要約:
      #{web_summary}

      ユーザーメモ:
      #{memo.presence || "（なし）"}
    USR

    gpt_text = nil
    begin
      resp = client.chat(
        parameters: {
          model:       "gpt-4o-mini",
          messages:    [
            { role: "system", content: system_prompt },
            { role: "user",   content: user_prompt }
          ],
          temperature: 0.3
        }
      )

      gpt_text = resp.dig("choices", 0, "message", "content").to_s.strip
    rescue => e
      Rails.logger.error("[OpenAI] #{e.class} #{e.message}")
      render json: { error: "生成に失敗しました。時間をおいて再度お試しください。" }, status: :bad_gateway and return
    end

    if gpt_text.blank?
      render json: { error: "AIから有効な文章を取得できませんでした。" }, status: :bad_gateway and return
    end

    # JS から meaning に反映させるだけでOK
    render json: { meaning: gpt_text }, status: :ok
  end
end