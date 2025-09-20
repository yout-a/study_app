OpenAI.configure do |config|
  config.access_token = ENV.fetch("OPENAI_API_KEY")
  # 任意: エラーをログ出力
  config.log_errors = true
end