# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2025_09_26_142635) do
  create_table "answer_selections", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "answer_id", null: false
    t.bigint "question_choice_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["answer_id"], name: "index_answer_selections_on_answer_id"
    t.index ["question_choice_id"], name: "index_answer_selections_on_question_choice_id"
  end

  create_table "answers", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "test_id", null: false
    t.bigint "question_id", null: false
    t.bigint "user_id", null: false
    t.boolean "correct"
    t.datetime "responded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["question_id"], name: "index_answers_on_question_id"
    t.index ["test_id"], name: "index_answers_on_test_id"
    t.index ["user_id"], name: "index_answers_on_user_id"
  end

  create_table "question_choices", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "question_id", null: false
    t.text "body"
    t.boolean "correct"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["question_id"], name: "index_question_choices_on_question_id"
  end

  create_table "questions", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "word_id", null: false
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["word_id"], name: "index_questions_on_word_id"
  end

  create_table "taggings", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "word_id", null: false
    t.bigint "tag_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
    t.index ["word_id", "tag_id"], name: "index_taggings_on_word_id_and_tag_id", unique: true
    t.index ["word_id"], name: "index_taggings_on_word_id"
  end

  create_table "tags", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "name"], name: "index_tags_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_tags_on_user_id"
  end

  create_table "test_questions", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "test_id", null: false
    t.bigint "question_id", null: false
    t.integer "position", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["question_id"], name: "fk_rails_733d15d143"
    t.index ["test_id", "position"], name: "index_test_questions_on_test_id_and_position", unique: true
  end

  create_table "test_taggings", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "test_id", null: false
    t.bigint "tag_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tag_id"], name: "index_test_taggings_on_tag_id"
    t.index ["test_id", "tag_id"], name: "index_test_taggings_on_test_id_and_tag_id", unique: true
    t.index ["test_id"], name: "index_test_taggings_on_test_id"
  end

  create_table "tests", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "scope"
    t.integer "item_count"
    t.integer "mode"
    t.integer "grading"
    t.integer "status"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "scope_names", comment: "選択時のタグ名を履歴として固定保存。カンマ区切り"
    t.index ["user_id"], name: "index_tests_on_user_id"
  end

  create_table "users", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "words", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "term", null: false
    t.text "meaning"
    t.text "memo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "term"], name: "index_words_on_user_id_and_term", unique: true
    t.index ["user_id"], name: "index_words_on_user_id"
  end

  add_foreign_key "answer_selections", "answers"
  add_foreign_key "answer_selections", "question_choices"
  add_foreign_key "answers", "questions"
  add_foreign_key "answers", "tests"
  add_foreign_key "answers", "users"
  add_foreign_key "question_choices", "questions"
  add_foreign_key "questions", "words"
  add_foreign_key "taggings", "tags"
  add_foreign_key "taggings", "words"
  add_foreign_key "tags", "users"
  add_foreign_key "test_questions", "questions"
  add_foreign_key "test_questions", "tests"
  add_foreign_key "test_taggings", "tags"
  add_foreign_key "test_taggings", "tests"
  add_foreign_key "tests", "users"
  add_foreign_key "words", "users"
end
