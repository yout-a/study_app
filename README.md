#usersテーブル
| Column           | Type   | Options                   |
| ---------------- | ------ | ------------------------- |
| name             | string | null: false               |
| email            | string | null: false, unique:true |
| password_digest | string | null: false               |

##Association
has_many :words
has_many :tests
has_many :questions

#words テーブル
| Column   | Type    | Options     |
| -------- | ------- | ----------- |
| term     | string  | null: false |
| meaning  | text    | null: false |
| memo     | text    |             |
| user_id | integer | null: false |

##Association
belongs_to :user
has_many :word_taggings
has_many :tags, through: :word_taggings

#tags テーブル
| Column | Type   | Options                   |
| ------ | ------ | ------------------------- |
| name   | string | null: false, unique:true |

##Association
has_many :word_taggings
has_many :words, through: :word_taggings

#word_taggings テーブル
| Column   | Type    | Options     |
| -------- | ------- | ----------- |
| word_id | integer | null: false |
| tag_id  | integer | null: false |

##Association
belongs_to :word
belongs_to :tag

#questions テーブル
| Column          | Type    | Options     |
| --------------- | ------- | ----------- |
| stem            | text    | null: false |
| kind            | string  | null: false |
| created_by_id | integer |             |

##Association
belongs_to :user, optional: true
has_many :question_choices

#question_choices テーブル
| Column       | Type    | Options     |
| ------------ | ------- | ----------- |
| question_id | integer | null: false |
| label        | string  | null: false |
| content      | text    | null: false |
| is_correct  | boolean | null: false |
| position     | integer | null: false |

##Association
belongs_to :question

#tests テーブル
| Column       | Type     | Options     |
| ------------ | -------- | ----------- |
| user_id     | integer  | null: false |
| scope        | string   |             |
| item_count  | integer  |             |
| direction    | string   |             |
| mode         | string   |             |
| grading      | string   |             |
| status       | string   |             |
| started_at  | datetime |             |
| finished_at | datetime |             |

##Association
belongs_to :user
has_many :test_questions
has_many :answers

#test_questions テーブル
| Column       | Type    | Options     |
| ------------ | ------- | ----------- |
| test_id     | integer | null: false |
| question_id | integer | null: false |
| position     | integer | null: false |

##Association
belongs_to :test
belongs_to :question

#answers テーブル
| Column          | Type     | Options        |
| --------------- | -------- | -------------- |
| test_id        | integer  | null: false    |
| question_id    | integer  | null: false    |
| answered_at    | datetime |                |
| time_spent_ms | integer  |                |
| flagged         | boolean  | default:false |
| skipped         | boolean  | default:false |
| is_correct     | boolean  |                |

##Association
belongs_to :test
belongs_to :question
has_many :answer_selections

#answer_selections テーブル
| Column     | Type    | Options     |
| ---------- | ------- | ----------- |
| answer_id | integer | null: false |
| choice_id | integer | null: false |

##Association
belongs_to :answer
belongs_to :question_choice