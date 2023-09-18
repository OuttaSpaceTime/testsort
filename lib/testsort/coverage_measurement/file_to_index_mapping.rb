module Testsort
  class CoverageMeasurement
    class FileToIndexMapping
      attr_reader :file_index
      attr_accessor :path_hash, :index_hash, :has_new_entries

      def initialize(params = {})
        @path_hash = params[:path_hash] || {}
        @index_hash = params[:index_hash] || {}
        @file_index = params[:path_hash]&.values&.last || -1
        @has_new_entries = false
      end

      def [](key)
        if key.instance_of?(String)
          @path_hash[key]
        elsif key.instance_of?(Integer)
          @index_hash[key]
        end
      end

      def fetch_specs(keys)
        index_hash.fetch_values(*keys)
      end

      def file_list
        @index_hash.values
      end

      def count
        @index_hash.values.count
      end

      def insert(path)
        if @path_hash.key?(path)
          @has_new_entries = false
          return
        end

        @file_index += 1
        @has_new_entries = true
        @path_hash[path] = @file_index
        @index_hash[@file_index] = path
      end

      def exclude?(path)
        @path_hash[path].blank?
      end

      def include?(path)
        @path_hash[path].present?
      end

      def empty?
        @path_hash.blank? && @index_hash.blank?
      end
    end
  end
end
