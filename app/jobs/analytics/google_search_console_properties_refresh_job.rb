class Analytics::GoogleSearchConsolePropertiesRefreshJob < ApplicationJob
  queue_as :default

  def perform(connection_id)
    connection = Analytics::GoogleSearchConsoleConnection.find_by(id: connection_id)
    return if connection.blank? || !connection.active?

    connection.refresh_verified_properties_now
  end
end
