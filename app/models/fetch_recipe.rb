# frozen_string_literal: true

class FetchRecipe < ApplicationRecord
  belongs_to :version
  belongs_to :library_source, optional: true

  validates :source_type, presence: true
  validates :url, presence: true
end
