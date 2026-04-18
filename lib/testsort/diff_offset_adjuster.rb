# frozen_string_literal: true

module Testsort
  class DiffOffsetAdjuster
    def self.adjust_lines(old_lines, hunks)
      return old_lines if hunks.blank?

      sorted_hunks = hunks.sort_by(&:old_start)
      old_lines.map { |line| adjust_single_line(line, sorted_hunks) }.compact
    end

    def self.adjust_spec_key(old_key, hunks)
      path, _, line_str = old_key.rpartition(':')
      return old_key if path.empty?
      return old_key unless line_str.match?(/\A[1-9]\d*\z/)

      old_line = line_str.to_i
      new_line = adjust_single_line(old_line, hunks.sort_by(&:old_start))
      return nil unless new_line

      "#{path}:#{new_line}"
    end

    def self.changed_old_lines(hunks)
      lines = []
      hunks.each do |hunk|
        hunk.each_line do |line|
          lines << line.old_lineno if line.line_origin == :deletion
        end
      end
      lines
    end

    def self.pure_insertion?(hunks)
      hunks.all? do |hunk|
        hunk.each_line.none? { |line| line.line_origin == :deletion }
      end
    end

    def self.adjust_single_line(old_line, sorted_hunks)
      cumulative_offset = 0

      sorted_hunks.each do |hunk|
        hunk_old_end = hunk.old_start + hunk.old_lines - 1

        if old_line < hunk.old_start
          return old_line + cumulative_offset
        elsif old_line <= hunk_old_end
          return nil if line_was_deleted?(old_line, hunk)
          return old_line + cumulative_offset + (hunk.new_lines - hunk.old_lines)
        end

        cumulative_offset += (hunk.new_lines - hunk.old_lines)
      end

      old_line + cumulative_offset
    end
    private_class_method :adjust_single_line

    def self.line_was_deleted?(old_line, hunk)
      hunk.each_line do |line|
        return true if line.old_lineno == old_line && line.line_origin == :deletion
      end
      false
    end
    private_class_method :line_was_deleted?
  end
end
