# app/controllers/tests_controller.rb
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
      grading: "batch"
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
  # app/controllers/tests_controller.rb （startだけ差し替え）
def start
  @test_setting = TestSettingForm.new(test_setting_params)
  unless @test_setting.valid?
    load_tags
    return render :new, status: :unprocessable_entity
  end

  # タグ選択の取得（単一/複数OK）
  raw_tag_ids   = @test_setting.respond_to?(:tag_ids) ? @test_setting.tag_ids : nil
  tag_ids       = Array(raw_tag_ids.presence || @test_setting.tag_id).reject(&:blank?).map(&:to_i)
  selected_tags = tag_ids.present? ? Tag.where(id: tag_ids) : Tag.none

  # 出題範囲（未習得フィルタは廃止済み）
  scope =
    if selected_tags.any? && Word.respond_to?(:by_tags)
      Word.by_tags(tag_ids)
    elsif Word.respond_to?(:by_tag)
      Word.by_tag(tag_ids.first)
    else
      Word.all
    end

  @questions = scope.order(Arel.sql("RAND()")).limit(@test_setting.question_count)

  # ★ enumの都合で必要なら scope を「合法キー」に自動設定
  scope_key =
    if Test.respond_to?(:defined_enums) && Test.defined_enums["scope"].present?
      Test.defined_enums["scope"].keys.first # 例: "unlearned" など
    end

  grading_mode = (@test_setting.grading.presence || "batch").to_s

  @test = Test.new(
    user:       current_user,
    item_count: @test_setting.question_count,
    mode:       @test_setting.question_type,
    grading:    grading_mode
  )
  @test.scope = scope_key if scope_key.present? && @test.respond_to?(:scope=)

  @test.save!

  # テスト⇔タグ紐づけ
  if selected_tags.any?
    if @test.respond_to?(:tags) && @test.tags.respond_to?(:<<)
      @test.tags = selected_tags
    elsif @test.respond_to?(:tag=)
      @test.tag = selected_tags.first
    end
  end

  # 履歴表示用ラベル（タグ名を固定保存）
  label = selected_tags.any? ? selected_tags.map(&:name).join("、") : "全単語"
  set_if_possible(@test, %i[scope_label scope_text range_label scope_names], label)
  @test.save! if @test.changed?

  # 選択肢も同じ範囲から
  choice_pool_words = scope.to_a

 ApplicationRecord.transaction do
  @questions.each.with_index(1) do |word, idx|
    kind = (idx.odd? ? :word_to_meaning : :meaning_to_word)

    pool = choice_pool_words.reject { |w| w.id == word.id }

    # ★★★ 追加：意味→単語が曖昧なら単語→意味に切り替え ★★★
    if kind == :meaning_to_word && ambiguous_meaning_to_word?(word, pool)
      kind = :word_to_meaning
    end

    # ---- Question を用意 ----
    q =
      if Question.reflect_on_association(:word)
        Question.find_or_initialize_by(word: word)
      else
        Question.new
      end

    # 出題文
    case kind
    when :word_to_meaning
      stem = "「#{word.term}」とは？"
      set_if_possible(q, %i[content text body title prompt statement], stem)
    else # :meaning_to_word
      stem = excerpt_for_meaning(word) # ← 下のprivateメソッド
      set_if_possible(q, %i[content text body title prompt statement], stem)
    end

    q.save! unless q.persisted?

    # 既存回答がある場合の複製/再生成（元コードのまま）
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

    # ---- 選択肢生成（プールは同じ範囲のみ） ----
    if kind == :word_to_meaning
      correct_text = safe_excerpt(word.meaning, banned: [word.term], max_len: 140)
      base = pool.map { |w| safe_excerpt(w.meaning, banned: [w.term, word.term], max_len: 140) }
                 .reject(&:blank?).uniq
      distractors = base.sample(3)
      while distractors.size < 3 && pool.any?
        filler = safe_excerpt(pool.sample.meaning, banned: [word.term], max_len: 140)
        distractors << filler if filler.present? && !distractors.include?(filler)
      end
      texts = ([correct_text] + distractors).shuffle

    else # :meaning_to_word（※曖昧性を再度ケア）
      correct_text = word.term.presence || "（単語未設定）"
      stem = excerpt_for_meaning(word)
      # ★ stemに当てはまって“正解になる”単語は誤選択肢から除外
      ambiguous_terms = pool.select { |w| excerpt_for_meaning(w) == stem }.map(&:term)
      base = pool.map(&:term).reject(&:blank?).uniq - ambiguous_terms
      distractors = base.sample(3)
      while distractors.size < 3 && base.any?
        filler = (base - distractors).sample
        break if filler.nil?
        distractors << filler
      end
      # それでも3つそろわない場合は安全のため単語→意味に作り直し
      if distractors.size < 3
        kind = :word_to_meaning
        correct_text = safe_excerpt(word.meaning, banned: [word.term], max_len: 140)
        base = pool.map { |w| safe_excerpt(w.meaning, banned: [w.term, word.term], max_len: 140) }
                   .reject(&:blank?).uniq
        distractors = base.sample(3)
        while distractors.size < 3 && pool.any?
          filler = safe_excerpt(pool.sample.meaning, banned: [word.term], max_len: 140)
          distractors << filler if filler.present? && !distractors.include?(filler)
        end
      end
      texts = ([correct_text] + distractors).shuffle
    end

      texts.each do |txt|
        attrs = { body: txt }
        if q.question_choices.new.respond_to?(:correct=)
          attrs[:correct] = (txt == correct_text)
        elsif q.question_choices.new.respond_to?(:is_correct=)
          attrs[:is_correct] = (txt == correct_text)
        end
        q.question_choices.create!(attrs)
      end

      @test.test_questions.create!(question: q, position: idx)
    end
  end

    redirect_to question_test_path(@test, pos: 1)
  rescue ActiveRecord::RecordInvalid => e
    load_tags
    msg = @test&.errors&.full_messages&.join(" / ").presence || e.message
    flash.now[:alert] = "テストの開始に失敗しました。#{msg}"
    render :new, status: :unprocessable_entity
  rescue => e
    load_tags
    Rails.logger.error("[TestsController#start] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    flash.now[:alert] = "テストの開始に失敗しました。#{e.message}"
    render :new, status: :unprocessable_entity
  end

  def show;  end

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

  include TagsHelper

  def load_tags
    raw = Tag.all
    @tags = sort_tags_gojuon(Tag.all)
  end

  def test_setting_params
    params.require(:test_setting_form).permit(
      :tag_id,
      :question_count,
      :question_type,
      :only_unlearned,        # ← 追加
      :grading,
      tag_ids: []             # 将来の複数選択用
    )
  end

  # 指定属性のうち存在する最初のものに値を入れる
  def set_if_possible(obj, attrs, value)
    attr = attrs.find { |a| obj.respond_to?(:"#{a}=") }
    obj.public_send("#{attr}=", value) if attr && value.present?
  end

  # 文章から禁止語を含まない1文を抜粋
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

  # 「意味→単語」用の抜粋（対象の単語名は含めない）
  def excerpt_for_meaning(word)
    safe_excerpt(word.meaning, banned: [word.term], max_len: 120)
  end

  # 指定wordの stem（意味抜粋）が、プール内の他の単語にも一致するか？
  def ambiguous_meaning_to_word?(word, pool_words)
    stem = excerpt_for_meaning(word)
    return false if stem.blank?
    pool_words.any? { |w| excerpt_for_meaning(w) == stem }
  end
end
