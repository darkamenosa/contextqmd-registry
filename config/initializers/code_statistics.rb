require "rails/code_statistics"

[
  [ "Frontend", "app/frontend", false ],
  [ "Frontend tests", "test/frontend", true ]
].each do |label, path, test_directory|
  next if Rails::CodeStatistics.directories.any? { |existing_label, existing_path| existing_label == label || existing_path == path }

  Rails::CodeStatistics.register_directory(label, path, test_directory:)
end

unless %w[jsx tsx mjs].all? { |extension| Rails::CodeStatistics.pattern.match?("file.#{extension}") }
  Rails::CodeStatistics.pattern = /^(?!\.).*?\.(rb|js|jsx|ts|tsx|mjs|css|scss|coffee|rake|erb)$/
end
