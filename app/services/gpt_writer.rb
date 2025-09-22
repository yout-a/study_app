# app/services/gpt_writer.rb
class GptWriter
  MODEL = (ENV["OPENAI_MODEL"].presence || "gpt-4o-mini")

  def self.rewrite(plain_text:, word:, memo:, max_chars: 500)
    return { meaning: nil, tags: [] } if plain_text.to_s.strip.empty?

    client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])

    # ...クラス定義などは既存のまま...

      system_prompt = <<~PROMPT
        あなたは日本語の百科要約ライターです。与えられた「事実テキスト」と「メモ」を根拠に、
        語「#{word}」の要約を #{max_chars} 文字以内で作成します。事実テキストに無い内容は書かない。

        1) まず対象の種別を推定しなさい:
          - person（人物） / organization（組織） / product（製品） / work（作品） / place（地名） / general（一般語）
        2) 出力は **meaning と tags のJSON**。meaning には以下の体裁で日本語を書き、先頭は必ず「#{word}は」または「【#{word}】は」で始める。Q&A形式（〜の意味は？）は禁止。

        [meaning の書式]
        - 種別が general（一般語）: 1〜3文の定義・用途のみ。
        - 種別が person / organization / product / work / place:
            （a）1〜2文の総括（概要）を最初に書く。
            （b）見出し「— 概要」を置き、1文で特徴や活動領域を要約。
            （c）見出し「— 略歴」を置き、年の古い順に最大6件の箇条書き（「・YYYY年 …」形式）。本文に年が無い場合は出来事の時系列が分かる順で。
            （d）本文に事実がある場合のみ、見出し「— 人物・エピソード」（または「— 特徴」）を置き、最大5件の箇条書き。
        - 全体で #{max_chars} 文字以内に収める。冗長な敬語・重複は避ける。

        [tags の指示]
        - 意味のある名詞・固有名詞のみ最大5件。途中で切れた断片や助詞は禁止。

        出力は必ずJSON:
        {
          "meaning": "<上記体裁の本文>",
          "tags": ["..."]
        }
      PROMPT

      user_input = <<~INPUT
        単語: #{word}
        メモ（関連）: #{memo}
        事実テキスト:
        #{plain_text}
      INPUT

    resp = client.chat(
      parameters: {
        model: MODEL,
        temperature: 0.3,
        # response_format をお好みで。JSONが壊れる場合は外してください。
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: user_input }
        ]
      }
    )

    raw  = resp.dig("choices", 0, "message", "content").to_s
    data = JSON.parse(raw) rescue {}

    meaning = data["meaning"].to_s.strip

    # ▼ ここを置き換え：タグのクリーニング
    tags = clean_tags(data["tags"])

    return { meaning: meaning, tags: tags } if meaning.present?

    { meaning: nil, tags: [] }
  rescue => e
    Rails.logger.warn("[GptWriter] #{e.class}: #{e.message}")
    { meaning: nil, tags: [] }
  end

  # ▼ 追加: タグ後処理
  def self.clean_tags(tags)
    stopwords = %w[の は が を に へ と で も や から まで など 等 系 型 こと もの 他]
    arr = Array(tags).map { |t| t.to_s.tr("　", " ").strip }
                     .reject(&:blank?)
                     .map { |t| t.gsub(/[、。！，．,.\(\)\[\]【】「」『』:：;；"']/u, "") }

    # 1文字 / ひらがな一文字 / ストップワード除外
    arr.select! { |t| t.length >= 2 && !(t =~ /\A[ぁ-ゖー]{1,2}\z/u) && !stopwords.include?(t) }

    # 「スペ」「シア」など “短い断片” を、同じ先頭を持つ長語があれば除外
    arr = arr.sort_by { |t| -t.length }
    filtered = []
    arr.each do |t|
      next if filtered.any? { |long| long.start_with?(t) && long.length > t.length && t.length <= 3 }
      filtered << t
    end

    filtered.uniq.first(5)
  end
end
