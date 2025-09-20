# app/services/tests/build_questions.rb
module Tests
  class BuildQuestions
    RANDOM_SQL =
      if ActiveRecord::Base.connection.adapter_name.match?(/mysql/i) then 'RAND()' else 'RANDOM()' end

    QUESTION_TEMPLATES = [
      ->(w){ "#{w.term} の意味は？" },
      ->(w){ "「#{w.term}」に最も近い説明はどれ？" },
      ->(w){ "#{w.term} を一言で言うと？" },
      ->(w){ "#{w.term} の定義として正しいものを選べ" }
    ]

    def initialize(test); @test = test; end

    def call
      words = pick_words
      return false if words.blank?

      @test.transaction do
        @test.test_questions.destroy_all

        words.each.with_index(1) do |word, idx|
          body = QUESTION_TEMPLATES.sample.call(word)   # ← ランダムな問題文
          q = Question.create!(word: word, body: body)

          # 正解1 + ダミー3
          q.question_choices.create!(body: word.meaning, correct: true)
          Word.where.not(id: word.id)
              .order(Arel.sql(RANDOM_SQL)).limit(3)
              .each { |w| q.question_choices.create!(body: w.meaning, correct: false) }

          @test.test_questions.create!(question: q, position: idx)
        end

        @test.update!(status: :running, started_at: Time.current)
      end
      true
    end

    private

    def pick_words
      scope_words =
        case @test.scope.to_sym
        when :unlearned then @test.user.words.limit(100)
        when :all_words then @test.user.words
        end
      scope_words.order(Arel.sql(RANDOM_SQL)).limit(@test.item_count)
    end
  end
end


