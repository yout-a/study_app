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

   # ===== 幅広い用語ノートに対応するプロンプト =====
    system_prompt = <<~SYS
    あなたは「個人ナレッジベース用の用語ノート」を作るアシスタントです。
    入力される用語/トピックは、英単語に限らず、技術用語・人名・サービス名・
    コマンド・ライブラリ・理論・出来事など幅広いものを想定します。
    更新時、#memo_textarea のデータを読み込んで、meaning に追加してください。

    次の JSON オブジェクト「だけ」を返してください（余計な文字や説明は禁止）:
    {
      "meaning": "用語の説明（日本語で500文字以内、簡潔で平易。）",
      "tags": ["短いラベル", "分野や用途", "..."]  // 最大5個、重複なし、記号や#は入れない
    }

    制約:
    - meaning: 日本語で500文字以内。専門外の読者にも伝わるよう簡潔に。断定調（〜である/〜する）。
    - 既存の説明が渡された場合は、それと矛盾しない範囲で要約・補足して品質を上げる。
    - tags: 分野・用途・関連概念などを短い名詞で。メモに分野/用途が書かれていれば優先して反映。
      最大5個、重複除去、記号・ハッシュ・長文を避ける。
    - #memo_textarea のデータをwebで検索した際に、関連情報も追加する。  
    - 不明/曖昧な場合は推測せず、
      meaning はwebで情報を取得して、
      tags は空配列 [] を返す。
    - 出力は JSON オブジェクトのみ。前後に説明・コードフェンスを付けない。
    SYS

    user_prompt = <<~USR
    用語: #{term}
    既存の説明: #{exist.presence || "（なし）"}
    補足メモ: #{memo.presence || "（なし）"}

    上記の制約に従い、指定の JSON だけを出力してください。
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

