# frozen_string_literal: true

class Version < ApplicationRecord
  belongs_to :library
  has_many :pages, dependent: :destroy
  has_many :bundles, dependent: :destroy
  has_one :fetch_recipe, dependent: :destroy

  validates :version, presence: true, uniqueness: { scope: :library_id }
  validates :channel, inclusion: { in: %w[stable latest canary snapshot] }

  scope :ordered, -> { order(generated_at: :desc) }
  scope :stable, -> { where(channel: "stable") }
end
