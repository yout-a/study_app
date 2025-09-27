class TestTagging < ApplicationRecord
  belongs_to :test
  belongs_to :tag
end
