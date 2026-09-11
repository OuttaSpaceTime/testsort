module Testsort
  module Agent
    # Extracts RSpec describe/context/it descriptions and their line numbers
    # from spec files via lightweight regex parsing. Lets a subagent receive
    # test descriptions alongside spec IDs without reading whole files.
    module Describe
      DESCRIBE_RX  = /^\s*(?:RSpec\.)?(?:describe|context)\s+(.+?)\s+do\b/
      IT_STR_RX    = /^\s*(?:it|specify|example)\s*(?:\([^)]*\)\s*)?["']([^"']+)["']\s*(?:do\b|,\s*[a-z_]+:|$)/
      IT_BLOCK_RX  = /^\s*(?:it|specify)\s*\{/
      IT_BARE_RX   = /^\s*(?:it|specify)\s+do\b/

      module_function

      # Returns { spec_path => [{ line:, full_description: }, ...] } for the
      # given file paths. Strips leading "./" from input paths.
      def describe_files(paths)
        paths.uniq.each_with_object({}) do |raw_path, out|
          path = raw_path.sub(/\A\.\//, '')
          next unless File.file?(path)

          out[path] = examples_for(path)
        end
      end

      def examples_for(path)
        lines = File.readlines(path)
        stack = []
        examples = []

        lines.each_with_index do |line, idx|
          line_no = idx + 1
          indent = line[/\A\s*/].size

          stack.pop while stack.any? && stack.last[:indent] >= indent

          if (m = line.match(DESCRIBE_RX))
            stack.push(indent: indent, desc: m[1].strip)
          elsif (m = line.match(IT_STR_RX))
            examples << build_example(stack, line_no, m[1].strip)
          elsif line.match?(IT_BLOCK_RX) || line.match?(IT_BARE_RX)
            examples << build_example(stack, line_no, '(implicit)')
          end
        end

        examples
      end

      def build_example(stack, line_no, desc)
        full = (stack.map { |s| s[:desc] } + [desc]).join(' > ')
        { line: line_no, full_description: full }
      end
    end
  end
end
