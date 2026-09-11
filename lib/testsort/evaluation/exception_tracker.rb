module Testsort
  module Evaluation
    class ExceptionTracker
      def initialize
        @exception_hash = Hash.new { Set.new }
      end

      def track(exception, exception_causing_line)
        if @exception_hash[exception].include?(exception_causing_line)
          false
        else
          add(exception, exception_causing_line)
          true
        end
      end

      def add(exception, exception_causing_line)
        @exception_hash[exception] = @exception_hash[exception].add(exception_causing_line)
      end

      # Serializes the (exception → set of locations) hash so a later run
      # can pre-seed itself with the same pairs (noise filtering: pairs we
      # already saw on the parent commit don't count as new faults).
      def to_h
        @exception_hash.transform_values { |set| set.to_a }
      end

      def self.from_file(path)
        tracker = new
        return tracker unless path && File.exist?(path)

        data = JSON.parse(File.read(path))
        data.each do |exception, locations|
          locations.each { |location| tracker.add(exception, location) }
        end
        tracker
      end

      # Merges one or more per-env source files into target_path.
      #
      # Loads target_path first (if it exists) so any data already there
      # (e.g. from process 1 which writes to the unsuffixed path) is
      # preserved. Then loads each source_path that exists, merges all
      # (exception, location) pairs into a single tracker, and dumps the
      # result to target_path. Source files are deleted after a successful
      # merge so stale per-env files don't accumulate.
      #
      # Idempotent: missing source_paths are silently skipped.
      # No-op when source_paths is empty and target_path doesn't exist.
      def self.merge_files(target_path, *source_paths)
        merged = from_file(target_path)

        source_paths.each do |src|
          next unless src && File.exist?(src)

          partial = from_file(src)
          partial.to_h.each do |exception, locations|
            locations.each { |location| merged.add(exception, location) }
          end
        end

        merged.dump_to(target_path)

        source_paths.each do |src|
          FileUtils.rm_f(src) if src && File.exist?(src)
        end
      end

      def dump_to(path)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.generate(to_h))
      end
    end
  end
end
