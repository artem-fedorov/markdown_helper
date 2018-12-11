require 'abbrev'
require 'pathname'
require 'uri'

require 'markdown_helper/version'

class MarkdownHelper

  class MarkdownHelperError < RuntimeError; end
  class CircularIncludeError < MarkdownHelperError; end
  class UnreadableInputError < MarkdownHelperError; end
  class TocHeadingsError < MarkdownHelperError; end
  class OptionError < MarkdownHelperError; end
  class EnvironmentError < MarkdownHelperError; end
  class InvalidTocTitleError < MarkdownHelperError; end
  class MisplacedPageTocError < MarkdownHelperError; end
  class MultiplePageTocError < MarkdownHelperError; end

  INCLUDE_REGEXP = /^@\[([^\[]+)\]\((.*?)\)$/
  LINK_REGEXP = /\[([^\[]+)\]\(([^)]+)\)$/

  attr_accessor :pristine

  def initialize(options = {})

    # Confirm that we're in a git project.
    # This is necessary so that we can prune file paths in the tests,
    # which otherwise would fail because of differing installation directories.
    # It also allows pruned paths to be used in the inserted comments (when not pristine).

    MarkdownHelper.git_clone_dir_path
    default_options = {
        :pristine => false,
    }
    merged_options = default_options.merge(options)
    merged_options.each_pair do |method, value|
      unless self.respond_to?(method)
        raise OptionError.new("Unknown option: #{method}")
      end
      setter_method = "#{method}="
      send(setter_method, value)
      merged_options.delete(method)
    end
  end

  def include(template_file_path, markdown_file_path)
    send(:generate_file, template_file_path, markdown_file_path, __method__) do |input_lines, output_lines|
      send(:include_files, template_file_path, input_lines, output_lines, Inclusions.new)
    end
  end

  def create_page_toc(markdown_file_path, toc_file_path)
    message = <<EOT
Method create_page_toc is deprecated.
Please use method include with embedded :page_toc treatment.
See https://github.com/BurdetteLamar/markdown_helper/blob/master/markdown/use_cases/include_files/include_page_toc/use_case.md#include-page-toc.
EOT
    warn(message)
    send(:generate_file, markdown_file_path, toc_file_path, __method__) do |input_lines, output_lines|
      send(:_create_page_toc, input_lines, output_lines)
    end
  end

  private

  class Heading

    attr_accessor :level, :title

    def initialize(level, title)
      self.level = level
      self.title = title
    end

    def self.parse(line)
      # Four leading spaces not allowed (but three are allowed).
      return nil if line.start_with?(' ' * 4)
      stripped_line = line.sub(/^ */, '')
      # Now must begin with hash marks and space.
      return nil unless stripped_line.match(/^#+ /)
      hash_marks, title = stripped_line.split(' ', 2)
      level = hash_marks.size
      # Seventh level heading not allowed.
      return nil if level > 6
      self.new(level, title)
    end


    def link
      remove_regexp = /[\#\(\)\[\]\{\}\.\?\+\*\`\"\']+/
      to_hyphen_regexp = /\W+/
      anchor = title.
          gsub(remove_regexp, '').
          gsub(to_hyphen_regexp, '-').
          downcase
      "[#{title}](##{anchor})"
    end

  end

  def self.comment(text)
    "<!--#{text}-->\n"
  end

  def generate_file(template_file_path, markdown_file_path, method)
    unless File.readable?(template_file_path)
      message = [
          Inclusions::UNREADABLE_INPUT_EXCEPTION_LABEL,
          template_file_path.inspect,
      ].join("\n")
      raise UnreadableInputError.new(message)
    end
    output_lines = []
    File.open(template_file_path, 'r') do |template_file|
      template_path_in_project = MarkdownHelper.path_in_project(template_file_path)
      output_lines.push(MarkdownHelper.comment(" >>>>>> BEGIN GENERATED FILE (#{method.to_s}): SOURCE #{template_path_in_project} ")) unless pristine
      input_lines = template_file.readlines
      yield input_lines, output_lines
      output_lines.push(MarkdownHelper.comment(" <<<<<< END GENERATED FILE (#{method.to_s}): SOURCE #{template_path_in_project} ")) unless pristine
    end
    File.open(markdown_file_path, 'w') do |file|
      output_lines.each do |line|
        file.write(line)
      end
    end
  end

  class PageInfo
    attr_accessor :path, :title, :prev_path, :prev_title, :next_path, :next_title
  end

  def _create_page_toc(input_lines, output_lines)
    first_heading_level = nil
    input_lines.each do |input_line|
      line = input_line.chomp
      heading = Heading.parse(line)
      next unless heading
      first_heading_level ||= heading.level
      indentation = '  ' * (heading.level - first_heading_level)
      output_line = "#{indentation}- #{heading.link}"
      output_lines.push("#{output_line}\n")
    end
  end

  def include_files(includer_file_path, input_lines, output_lines, inclusions)
    markdown_lines = []
    page_toc_inclusion = nil
    page_nav_regexp = nil
    input_lines.each_with_index do |input_line, line_index|
      match_data = input_line.match(INCLUDE_REGEXP)
      unless match_data
        markdown_lines.push(input_line)
        next
      end
      treatment = match_data[1]
      cited_includee_file_path = match_data[2]
      new_inclusion = Inclusion.new(
          input_line.chomp,
          includer_file_path,
          line_index + 1,
          cited_includee_file_path,
          treatment
      )
      case treatment
      when ':markdown'
        inclusions.include(
            new_inclusion,
            markdown_lines,
            self
        )
      when ':page_toc'
        unless inclusions.inclusions.size == 0
          message = 'Page TOC must be in outermost markdown file.'
          raise MisplacedPageTocError.new(message)
        end
        unless page_toc_inclusion.nil?
          message = 'Only one page TOC allowed.'
          raise MultiplePageTocError.new(message)
        end
        page_toc_inclusion = new_inclusion
        toc_title = match_data[2]
        title_regexp = /^\#{1,6}\s/
        unless toc_title.match(title_regexp)
          message = "TOC title must be a valid markdown header, not #{toc_title}"
          raise InvalidTocTitleError.new(message)
        end
        page_toc_inclusion.page_toc_title = toc_title
        page_toc_inclusion.page_toc_line = input_line
        markdown_lines.push(input_line)
      when ':page_nav'
        page_nav_regexp = Regexp.new(match_data[2])
      else
        markdown_lines.push(input_line)
      end
    end
    # If needed, create page TOC and insert into markdown_lines.
    unless page_toc_inclusion.nil?
      toc_lines = [
          page_toc_inclusion.page_toc_title + "\n",
          '',
      ]
      page_toc_index =  markdown_lines.index(page_toc_inclusion.page_toc_line)
      lines_to_scan = markdown_lines[page_toc_index + 1..-1]
      _create_page_toc(lines_to_scan, toc_lines)
      markdown_lines.delete_at(page_toc_index)
      markdown_lines.insert(page_toc_index, *toc_lines)
    end
    def common_path(path_0, path_1)
      dirs = [path_0, path_1]
      common_prefix = dirs.abbrev.keys.min_by {|key| key.length}.chop
      common_prefix.sub(%r{/[^/]*$}, '')
    end
    if page_nav_regexp
      page_infos = []
      markdown_lines.each do |markdown_line|
        next unless markdown_line.match(page_nav_regexp)
        match_data = markdown_line.match(LINK_REGEXP)
        unless match_data.nil?
          page_info = PageInfo.new
          page_infos.push(page_info)
          url = match_data[2]
          uri = URI.parse(url)
          path = uri.path
          page_info.path = path
          next unless path.end_with?('.md')
          File.readlines(path).each do |line|
            if line.match(/^#+ /)
              title = line.split(/ /)[1..-1].join(' ')
              page_info.title = title.chomp
              break
            end
          end
        end
      end
      page_infos.each_with_index do |page_info, i|
        if i == 0
          page_info.prev_path = nil
          page_info.prev_title = nil
        else
          prev_info = page_infos[i - 1]
          page_info.prev_path = prev_info.path
          page_info.prev_title = prev_info.title
        end
        if i == page_infos.size - 1
          page_info.next_path = nil
          page_info.next_title = nil
        else
          next_info = page_infos[i + 1]
          page_info.next_path = next_info.path
          page_info.next_title = next_info.title
        end
        path = page_info.path
        if page_info.prev_path
          prev_path = page_info.prev_path
          prev_relative_path = prev_path.sub(common_path(path, prev_path), '..')
        end
        if page_info.next_path
          next_path = page_info.next_path
          next_relative_path = next_path.sub(common_path(path, next_path), '..')
        end
        # Github flavored markdown is *very* picky about whitespace in a table,
        # so form carefully for each case.
        nav_table = case
                    when page_info.next_path.nil?
                      <<EOT
<table>
  <tr>
    <th>Prev</th>
    <td><a href="#{prev_relative_path}">#{page_info.prev_title}</a></td>
  </tr>
</table>
EOT
                    when page_info.prev_path.nil?
                      <<EOT
<table>
  <tr>
    <th>Next</th>
    <td><a href="#{next_relative_path}">#{page_info.next_title}</a></td>
  </tr>
</table>
EOT
                    else
                      <<EOT
<table>
  <tr>
    <th>Prev</th>
    <td><a href="#{prev_relative_path}">#{page_info.prev_title}</a></td>
  </tr>
  <tr>
    <th>Next</th>
    <td><a href="#{next_relative_path}">#{page_info.next_title}</a></td>
  </tr>
</table>
EOT
                    end
        lines = File.readlines(page_info.path)
        lines.unshift(nav_table, "\n")
        lines.push("\n", nav_table)
        File.write(page_info.path, lines.join)
      end
    end
    # Now review the markdown and include everything.
    markdown_lines.each_with_index do |markdown_line, line_index|
      match_data = markdown_line.match(INCLUDE_REGEXP)
      unless match_data
        output_lines.push(markdown_line)
        next
      end
      treatment = match_data[1]
      cited_includee_file_path = match_data[2]
      new_inclusion = Inclusion.new(
          markdown_line.chomp,
          includer_file_path,
          line_index + 1,
          cited_includee_file_path,
          treatment
      )
      inclusions.include(
          new_inclusion,
          output_lines,
          self
      )
    end
  end

  def self.git_clone_dir_path
    git_dir = `git rev-parse --show-toplevel`.chomp
    unless $?.success?
      message = <<EOT

Markdown helper must run inside a .git project.
That is, the working directory one of its parents must be a .git directory.
EOT
      raise RuntimeError.new(message)
    end
    git_dir
  end

  def self.path_in_project(path)
    path.sub(MarkdownHelper.git_clone_dir_path + '/', '')
  end

  class Inclusions

    attr_accessor :inclusions

    def initialize
      self.inclusions = []
    end

    def include(
      new_inclusion,
      output_lines,
      markdown_helper
    )
      treatment = case new_inclusion.treatment
                    when ':code_block'
                      :code_block
                    when ':markdown'
                      :markdown
                    when ':verbatim'
                      message = "Treatment ':verbatim' is deprecated; please use treatment ':markdown'."
                      warn(message)
                      :markdown
                    when ':comment'
                      :comment
                    when ':pre'
                      :pre
                    else
                      new_inclusion.treatment
                  end
      if treatment == :markdown
        check_circularity(new_inclusion)
      end
       includee_path_in_project = MarkdownHelper.path_in_project(new_inclusion.absolute_includee_file_path)
      output_lines.push(MarkdownHelper.comment(" >>>>>> BEGIN INCLUDED FILE (#{treatment}): SOURCE #{includee_path_in_project} ")) unless markdown_helper.pristine
      begin
        include_lines = File.readlines(new_inclusion.absolute_includee_file_path)
      rescue => e
        inclusions.push(new_inclusion)
        message = [
            MISSING_INCLUDEE_EXCEPTION_LABEL,
            backtrace_inclusions,
        ].join("\n")
        e = UnreadableInputError.new(message)
        e.set_backtrace([])
        raise e
      end
      last_line = include_lines.last
      unless last_line && last_line.match("\n")
        message = "Warning:  Included file has no trailing newline: #{new_inclusion.cited_includee_file_path}"
        warn(message)
      end
      case treatment
        when :markdown
          # Pass through unadorned, but honor any nested includes.
          inclusions.push(new_inclusion)
          markdown_helper.send(:include_files, new_inclusion.absolute_includee_file_path, include_lines, output_lines, self)
          inclusions.pop
        when :comment
          output_lines.push(MarkdownHelper.comment(include_lines.join('')))
        when :pre
          output_lines.push("<pre>\n")
          output_lines.push(include_lines.join(''))
          output_lines.push("</pre>\n")
        else
          # Use the file name as a label.
          file_name_line = format("```%s```:\n", File.basename(new_inclusion.cited_includee_file_path))
          output_lines.push(file_name_line)
          # Put into code block.
          language = treatment == :code_block ? '' : treatment
          output_lines.push("```#{language}\n")
          output_lines.push(*include_lines)
          output_lines.push("```\n")
      end
      output_lines.push(MarkdownHelper.comment(" <<<<<< END INCLUDED FILE (#{treatment}): SOURCE #{includee_path_in_project} ")) unless markdown_helper.pristine
    end

    CIRCULAR_EXCEPTION_LABEL = 'Includes are circular:'
    UNREADABLE_INPUT_EXCEPTION_LABEL = 'Could not read input file.'
    UNWRITABLE_OUTPUT_EXCEPTION_LABEL = 'Could not write output file.'
    MISSING_INCLUDEE_EXCEPTION_LABEL = 'Could not read include file,'
    LEVEL_LABEL = '    Level'
    BACKTRACE_LABEL = '  Backtrace (innermost include first):'

    def check_circularity(new_inclusion)
      previous_inclusions = inclusions.collect {|x| x.real_includee_file_path}
      previously_included = previous_inclusions.include?(new_inclusion.real_includee_file_path)
      if previously_included
        inclusions.push(new_inclusion)
        message = [
            CIRCULAR_EXCEPTION_LABEL,
            backtrace_inclusions,
            ].join("\n")
        e = MarkdownHelper::CircularIncludeError.new(message)
        e.set_backtrace([])
        raise e
      end
    end

    def backtrace_inclusions
      lines = [BACKTRACE_LABEL]
      inclusions.reverse.each_with_index do |inclusion, i|
        lines.push("#{LEVEL_LABEL} #{i}:")
        level_lines = inclusion.to_lines(indentation_level = 3)
        lines.push(*level_lines)
      end
      lines.join("\n")
    end

  end

  class Inclusion

    LINE_COUNT = 5

    attr_accessor \
      :includer_file_path,
      :includer_line_number,
      :include_description,
      :absolute_includee_file_path,
      :cited_includee_file_path,
      :treatment,
      :page_toc_title,
      :page_toc_line

    def initialize(
        include_description,
        includer_file_path,
        includer_line_number,
        cited_includee_file_path,
        treatment
    )
      self.include_description = include_description
      self.includer_file_path = includer_file_path
      self.includer_line_number = includer_line_number
      self.cited_includee_file_path = cited_includee_file_path
      self.absolute_includee_file_path = absolute_includee_file_path
      self.treatment = treatment
      self.absolute_includee_file_path = File.absolute_path(File.join(
          File.dirname(includer_file_path),
          cited_includee_file_path,
      ))
    end

    def real_includee_file_path
      # Would raise exception unless exists.
      return nil unless File.exist?(absolute_includee_file_path)
      Pathname.new(absolute_includee_file_path).realpath.to_s
    end

    def indentation(level)
      '  ' * level
    end

    def to_lines(indentation_level)
      relative_inluder_file_path = MarkdownHelper.path_in_project(includer_file_path)
      relative_inludee_file_path = MarkdownHelper.path_in_project(absolute_includee_file_path)
       text = <<EOT
#{indentation(indentation_level)}Includer:
#{indentation(indentation_level+1)}Location: #{relative_inluder_file_path}:#{includer_line_number}
#{indentation(indentation_level+1)}Include description: #{include_description}
#{indentation(indentation_level)}Includee:
#{indentation(indentation_level+1)}File path: #{relative_inludee_file_path}
EOT
      text.split("\n")
    end

  end

end

