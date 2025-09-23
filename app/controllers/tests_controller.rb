class TestsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_test,  only: [:show, :result, :resume]
  before_action :load_tags, only: [:new, :create]

  # 設定画面
  def new
    @test_setting = TestSettingForm.new(
      tag_id: nil,             # 全タグ
      only_unlearned: true,    # 既定：未習得のみ
      question_count: 10,
      question_type: "single",
      scoring: "batch"
    )
  end

  # 互換のため残す（副作用なしで new に戻すだけ）
  def create
    @test_setting = TestSettingForm.new(test_setting_params)
    if @test_setting.valid?
      flash.now[:notice] = "設定を確認しました。そのまま「テスト開始」を押してください。"
      render :new, status: :ok
    else
      render :new, status: :unprocessable_entity
    end
  end

  # テスト開始
  def start
    @test_setting = TestSettingForm.new(test_setting_params)
    unless @test_setting.valid?
      load_tags
      return render :new, status: :unprocessable_entity
    end

    # 出題抽出（タグ＆未習得フィルタ）
    scope = Word.by_tag(@test_setting.tag_id)
    if ActiveModel::Type::Boolean.new.cast(@test_setting.only_unlearned)
      scope = scope.respond_to?(:unlearned) ? scope.unlearned : scope
    end
    @questions = scope.order(Arel.sql("RAND()")).limit(@test_setting.question_count)

    # Test 作成（scope は enum を想定して既存値のみ）
    scope_name = ActiveModel::Type::Boolean.new.cast(@test_setting.only_unlearned) ? "unlearned" : "all"
    test_attrs = {
      user:       current_user,
      scope:      scope_name,
      item_count: @test_setting.question_count,
      mode:       @test_setting.question_type, # enum 想定: single/multiple
      grading:    @test_setting.scoring       # enum 想定: batch/instant
    }

    @test = Test.new(test_attrs)

    if @test.save
      # 4択用のダミー候補を引くプール（自分以外）
      all_words_for_choices = Word.where.not(id: @questions.map(&:id)).to_a
      # もし出題数が少なくプールが足りない場合は全体から補完
      all_words_for_choices = Word.all.to_a if all_words_for_choices.size < 10

      ApplicationRecord.transaction do
        @questions.each.with_index(1) do |word, idx|
          # --- 2種類の問題タイプを半々で生成 ---------------
          # ① 単語→意味 を選択
          # ② 意味→単語 を選択
          kind = (idx.odd? ? :word_to_meaning : :meaning_to_word)

          # ---- Question（本文 = 問題文）を用意 --------------
          q =
            if Question.reflect_on_association(:word)
              Question.find_or_initialize_by(word: word)
            else
              Question.new
            end

          # 出題文
          case kind
          when :word_to_meaning
            # A) 単語 → 解説を選ぶ：出題文は「<単語>とは？」
            stem = "「#{word.term}」とは？"
            set_if_possible(q, %i[content text body title prompt statement], stem)
          when :meaning_to_word
            # B) 解説 → 単語を選ぶ：出題文は単語名を含まない抜粋
            stem = safe_excerpt(word.meaning, banned: [word.term], max_len: 120)
            set_if_possible(q, %i[content text body title prompt statement], stem)
          end

          q.save! unless q.persisted?

          # ---- 4択の作成（既存が回答に使われていれば複製、それ以外は作り直し） ----
          if q.respond_to?(:question_choices)
            choice_ids  = q.question_choices.select(:id)
            has_answers = q.persisted? && AnswerSelection.where(question_choice_id: choice_ids).exists?

            if has_answers
              dup_q = q.dup
              dup_q.word = q.word if dup_q.respond_to?(:word=)
              dup_q.save!
              q = dup_q
            else
              q.question_choices.destroy_all
            end
          end

          # 正解テキスト & 誤選択肢ソース
          if kind == :word_to_meaning
            # 正解は “単語名を含まない” 意味の抜粋
            correct_text = safe_excerpt(word.meaning, banned: [word.term], max_len: 140)

            # 誤選択肢：他語の意味から抜粋（自語名 & その語の名前を除外）
            pool = all_words_for_choices.reject { |w| w.id == word.id }
            distractors = pool.map { |w| safe_excerpt(w.meaning, banned: [w.term, word.term], max_len: 140) }
                              .reject(&:blank?).uniq
            distractors = distractors.sample(3)
            while distractors.size < 3
              filler = safe_excerpt(pool.sample&.meaning, banned: [word.term], max_len: 140)
              distractors << filler if filler.present? && !distractors.include?(filler)
            end

            texts = ([correct_text] + distractors).shuffle
          else # :meaning_to_word
            # 正解：単語名
            correct_text = word.term.presence || "（単語未設定）"

            # 誤選択肢：他語の単語名
            pool = all_words_for_choices.reject { |w| w.id == word.id }
            distractors = pool.map(&:term).reject(&:blank?).uniq.sample(3)
            while distractors.size < 3
              filler = pool.sample&.term
              distractors << filler if filler.present? && !distractors.include?(filler)
            end

            texts = ([correct_text] + distractors).shuffle
          end

          # correct フラグ名の違いに配慮（:correct か :is_correct を両対応）
          texts.each do |txt|
            attrs = { body: txt }
            if q.question_choices.new.respond_to?(:correct=)
              attrs[:correct] = (txt == correct_text)
            elsif q.question_choices.new.respond_to?(:is_correct=)
              attrs[:is_correct] = (txt == correct_text)
            end
            q.question_choices.create!(attrs)
          end

          # ---- テスト順序に並べる ----
          @test.test_questions.create!(question: q, position: idx)
        end
      end

      # 成功時
      redirect_to question_test_path(@test, pos: 1)
    else
      # 失敗時
      load_tags
      flash.now[:alert] = @test.errors.full_messages.join("\n")
      render :new, status: :unprocessable_entity
    end
  end

  def show
  end

  def result
    @total    = @test.test_questions.count
    @answers  = @test.answers.includes(:question, :question_choices)
    @corrects = @answers.where(correct: true).count
    @rate     = @total.zero? ? 0 : (@corrects * 100.0 / @total).round
    @wrongs   = @answers.where(correct: false)
  end

  # 途中再開
  def resume
    answered_qids = Answer.where(test: @test, user: current_user).pluck(:question_id)
    tq = @test.test_questions.where.not(question_id: answered_qids).order(:position).first
    pos = (tq&.position || @test.test_questions.minimum(:position) || 1)
    redirect_to question_test_path(@test, pos: pos)
  end

  private

  def set_test
    @test = current_user.tests.find(params[:id])
  end

  def load_tags
    @tags = Tag.order(:name)
  end

  def test_setting_params
    params.require(:test_setting_form).permit(
      :tag_id, :only_unlearned, :question_count, :question_type, :scoring
    )
  end

  # 指定属性のうち存在する最初のものに値を入れる
  def set_if_possible(obj, attrs, value)
    attr = attrs.find { |a| obj.respond_to?(:"#{a}=") }
    obj.public_send("#{attr}=", value) if attr && value.present?
  end

  # 文章から禁止語を含まない1文を抜粋（残っていれば除去）して返す
  def safe_excerpt(text, banned:, max_len: 140)
    return "" if text.blank?
    t = text.to_s.gsub(/\r\n|\r|\n/, "。")
    sentences = t.split(/[。！？!?]/).map(&:strip).reject(&:blank?)
    banned = Array(banned).compact.uniq

    s = sentences.find { |sen| banned.none? { |w| w.present? && sen.include?(w) } } || sentences.first || t
    banned.each { |w| s = s.gsub(Regexp.new(Regexp.escape(w)), "") if w.present? }
    s = s.strip
    s.length > max_len ? "#{s[0, max_len]}…" : s
  end
end
