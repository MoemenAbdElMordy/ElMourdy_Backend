require "test_helper"

class EnglishOnlyTest < ActiveSupport::TestCase
  ARABIC_SCRIPT = /\p{Arabic}/
  TEXT_EXTENSIONS = %w[
    .css .erb .example .html .md .rb .ru .rake .txt .xml .yml .yaml
  ].freeze
  TEXT_FILENAMES = %w[
    .dockerignore .gitignore .ruby-version Dockerfile Gemfile Rakefile
  ].freeze
  EXCLUDED_DIRECTORIES = %w[
    .git log storage tmp vendor
  ].freeze

  test "backend source and documentation use English only" do
    violations = project_text_files.filter_map do |path|
      next unless File.read(path, mode: "r:BOM|UTF-8").match?(ARABIC_SCRIPT)

      path.relative_path_from(Rails.root).to_s
    end

    assert_empty violations,
      "Arabic script is not allowed in backend source or documentation: #{violations.join(', ')}"
  end

  private

  def project_text_files
    Rails.root.glob("**/*", File::FNM_DOTMATCH).select do |path|
      relative_path = path.relative_path_from(Rails.root)

      path.file? &&
        EXCLUDED_DIRECTORIES.exclude?(relative_path.each_filename.first) &&
        (TEXT_EXTENSIONS.include?(path.extname) || TEXT_FILENAMES.include?(path.basename.to_s))
    end
  end
end
