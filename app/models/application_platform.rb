# frozen_string_literal: true

class ApplicationPlatform
  def initialize(user_agent)
    @user_agent = user_agent.to_s
  end

  def ios?
    match?(/iPhone|iPad/)
  end

  def android?
    match?(/Android/)
  end

  def mobile?
    ios? || android?
  end

  def desktop?
    !mobile?
  end

  def native?
    match?(/Hotwire Native/)
  end

  def type
    if native? && android?
      "native android"
    elsif native? && ios?
      "native ios"
    elsif mobile?
      "mobile web"
    else
      "desktop web"
    end
  end

  private

    def match?(pattern)
      @user_agent.match?(pattern)
    end
end
