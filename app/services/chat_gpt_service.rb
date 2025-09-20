class ChatGptService
  def initialize
    @client = OpenAI::Client.new
  end

  # 単語から意味とタグを提案させる
  def suggest_for_word(term)
    prompt = <<~PROMPT
      次の単語について簡潔な意味（日本語）と関連するタグ（カンマ区切り）を提案してください。
      単語: #{term}

      出力フォーマット:
      意味: ...
      タグ: ...
    PROMPT

    response = @client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: [{ role: "user", content: prompt }],
        temperature: 0.7
      }
    )

    text = response.dig("choices", 0, "message", "content")
    parse_response(text)
  end

  private

  def parse_response(text)
    meaning = text[/意味[:：]\s*(.+)/, 1]
    tags    = text[/タグ[:：]\s*(.+)/, 1]

    { meaning: meaning, tags: tags }
  end
end
