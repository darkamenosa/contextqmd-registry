# frozen_string_literal: true

class FetchRecipe < ApplicationRecord
  belongs_to :version

  validates :source_type, presence: true
  validates :url, presence: true
end
