class GptWriter
  MODEL = (ENV["OPENAI_MODEL"].presence || "gpt-4o-mini")

  def self.rewrite(plain_text:, word:, memo:, max_chars: 500, type_hint: nil)
    return { meaning: nil, tags: [] } if plain_text.to_s.strip.empty?

    client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])

    system_prompt = <<~PROMPT
      あなたは日本語の百科要約ライターです。与えられた「事実テキスト」と「メモ」を根拠に、
      語「#{word}」の要約を最大#{max_chars}文字で作成します。出典に無い推測・Q&A形式は禁止。
      分類ヒントが "person" の場合は「概要｜略歴｜人物エピソード」、
      "thing" の場合は「概要｜小史｜エピソード/トリビア」をこの順で一段落に含めること。
      出力は JSON のみ {"meaning":"...", "tags": []}。JSON以外は出力しない。
    PROMPT

    user_input = <<~INPUT
      単語: #{word}
      分類ヒント: #{type_hint || "（なし）"}
      メモ: #{memo}
      事実テキスト:
      #{plain_text}
    INPUT

    resp = client.chat(parameters: {
      model: MODEL, temperature: 0.3,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: system_prompt },
        { role: "user",   content: user_input }
      ]
    })

    raw  = resp.dig("choices", 0, "message", "content").to_s
    data = safe_parse_json_object(raw)     # ← ここが重要

    meaning = data["meaning"].to_s.strip
    tags    = clean_tags(data["tags"])

    return { meaning: meaning, tags: tags } if meaning.present?
    { meaning: nil, tags: [] }
  rescue => e
    Rails.logger.warn("[GptWriter] #{e.class}: #{e.message}")
    { meaning: nil, tags: [] }
  end

  # 追加：安全パース
  def self.safe_parse_json_object(str)
    if (m = str.match(/```json\s*(\{.*?\})\s*```/m))
      begin; return JSON.parse(m[1]); rescue; end
    end
    if (m = str.match(/\{.*\}/m))
      begin; return JSON.parse(m[0]); rescue; end
    end
    # Ruby風 {:meaning=>"..", :tags=>[...]} をJSONへ寄せる
    begin
      s = str.dup
      s.gsub!(/:(\w+)\s*=>/, '"\1":')  # :key=> → "key":
      s.gsub!("=>", ":")
      s.gsub!(/:(\w+)(?=[\s,\}])/, '"\1"')
      s.gsub!(/\bnil\b/, "null")
      return JSON.parse(s)
    rescue
      { "meaning" => nil, "tags" => [] } # 生文字列は返さない
    end
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
