require "openai"
require "json"

class GptWriter
  MODEL = (ENV["OPENAI_MODEL"].presence || "gpt-4o-mini")

  def self.rewrite(plain_text:, word:, memo:, max_chars: 500)
    return { meaning: nil, tags: [] } if plain_text.to_s.strip.empty?

    client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])

    system_prompt = <<~PROMPT
      あなたは日本語の百科要約ライターです。
      与えられた「事実テキスト」を根拠に、憶測や創作を加えず #{max_chars}字以内で
      一般読者向けに自然で読みやすい説明を書いてください。
      重要: 事実テキストにない内容は書かない。数値/日付/固有名は改変しない。
      メモの語は観点や検索語として活用してよいが、事実テキストに矛盾する場合は採用しない。
      出力は必ず次のJSONのみ：
      {
        "meaning": "<#{max_chars}字以内の本文。文末は「。」で終える>",
        "tags": ["最大5件。検索語として機能する固有名・カテゴリ・関連語（日本語）。重複・曖昧語なし。"]
      }
    PROMPT

    user_input = <<~INPUT
      語: #{word}
      メモ: #{memo}
      事実テキスト:
      #{plain_text}
    INPUT

    resp = client.chat(
      parameters: {
        model: MODEL,
        temperature: 0.3,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: system_prompt },
          { role: "user",   content: user_input }
        ]
      }
    )

    raw  = resp.dig("choices", 0, "message", "content").to_s
    data = JSON.parse(raw) rescue {}
    meaning = data["meaning"].to_s.strip
    tags    = Array(data["tags"]).map(&:to_s).reject(&:empty?).uniq.first(5)
    return { meaning: meaning, tags: tags } if meaning.present?

    { meaning: nil, tags: [] }
  rescue => e
    Rails.logger.warn("[GptWriter] #{e.class}: #{e.message}")
    { meaning: nil, tags: [] }
  end
end
