require_relative 'include_files/include_use_case'
require_relative '../../lib/string_helper'

namespace :build do

  def camelize(snake_case_string)
    snake_case_string.split('_').collect(&:capitalize).join
  end

  desc 'Build use case markdown'
  task :use_cases do
    # Page that links to use cases.
    File.open('use_cases.md', 'w') do |use_case_file|
      use_case_file.puts(<<EOT
# Use Cases

@[:page_nav](./__page_nav__)
EOT
      )
      dir_path = File.dirname(__FILE__)
      Dir.chdir(dir_path) do
        IncludeUseCase.write_interface_file
        use_case_dirs = {
            :include_files => %w/
                reuse_text
                nest_inclusions
                include_markdown
                include_code_block
                include_highlighted_code
                include_page_toc
                include_text_as_comment
                include_text_as_pre
                include_generated_text
                include_with_added_comments
                diagnose_missing_includee
                diagnose_circular_includes
            /,

            # include_page_toc

            # :tables_of_contents => %w/
            #     create_and_include_page_toc
            # /,
        }
        use_case_dirs.each_pair do |section, dir_names|

          # Header for section, if any dirs therein.
          title = StringHelper.to_title(section.to_s).sub(/ toc$/i, ' TOC')
          use_case_file.puts(<<EOT
## #{title}

EOT
) unless dir_names.empty?

          # Be careful with use case that has a backtrace.
          backtrace_cases = %w/
              diagnose_missing_includee
              diagnose_circular_includes
          /

          # Each use case is in a separate directory.
          dir_names.each do |dir_name|
            Dir.chdir("#{section}/#{dir_name}") do

              # There should be a conventionally-named ruby file to build the use case.
              fail dir_name unless File.exist?(UseCase::BUILDER_FILE_NAME)

              # There should be a conventionally-named use-case template.
              fail dir_name unless File.exist?(UseCase::TEMPLATE_FILE_NAME)

              class_name = camelize(dir_name)
              command = "ruby -I . -r #{UseCase::BUILDER_FILE_NAME} -e #{class_name}.build"
              if backtrace_cases.include?(dir_name)
                command += " 2> #{dir_name}.err"
                begin
                  system(command)
                rescue
                  #
                end
              else
                system(command)
              end

              title_line = File.open(UseCase::TEMPLATE_FILE_NAME).grep(/^#/).first.chomp
              title = title_line.split(/\s/, 2).pop
              use_case_file_name = File.basename(UseCase::USE_CASE_FILE_NAME)
              use_case_anchor = dir_name.gsub('_', '-')
              use_case_relative_url = File.join(
                  section.to_s,
                  dir_name,
                  use_case_file_name + '#' + use_case_anchor,
              )
              use_case_file.puts("* [#{title}](#{use_case_relative_url})")
            end
          end
        end
      end
    end
    # Now have the file include so the page_nav gets built.
    require 'markdown_helper'
    MarkdownHelper.new.include('use_cases.md', 'use_cases.md')
  end

end
