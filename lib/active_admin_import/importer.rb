# frozen_string_literal: true
require 'csv'
module ActiveAdminImport
  class Importer
    attr_reader :resource, :options, :result, :model
    attr_accessor :csv_rows

    OPTIONS = [
      :validate,
      :on_duplicate_key_update,
      :on_duplicate_key_ignore,
      :ignore,
      :timestamps,
      :before_import,
      :after_import,
      :before_batch_import,
      :after_batch_import,
      :batch_size,
      :batch_transaction,
      :csv_options
    ].freeze

    def initialize(resource, model, options)
      @resource = resource
      @model = model
      assign_options(options)
    end

    def import_result
      @import_result ||= ImportResult.new
    end

    def file
      @model.file
    end

    def cycle(rows)
      @csv_rows = rows
      import_result.add(batch_import, rows.count)
    end

    def import
      run_callback(:before_import)
      process_file
      run_callback(:after_import)
      import_result
    end

    def import_options
      @import_options ||= options.slice(
        :validate,
        :validate_uniqueness,
        :on_duplicate_key_update,
        :on_duplicate_key_ignore,
        :ignore,
        :timestamps,
        :batch_transaction,
        :batch_size
      )
    end

    def batch_replace(header_key, options)
      # TODO test me this is just a guess
      # index = header_index(header_key)
      @csv_rows.map! do |row|
        from = row[header_key]
        row[header_key] = options[from] if options.key?(from)
        row
      end
    end

    protected

    def process_file
      rows = []
      batch_size = options[:batch_size].to_i

      CSV::foreach(File.open(file.path), @csv_options) do |row|
        rows << row unless row.blank? #blank line maybe?
        if rows.size == batch_size
          cycle(rows)
          rows = []
        end
      end
      # get the last batch that is smaller than batch_size
      cycle(rows) unless rows.blank?
    end

    def run_callback(name)
      options[name].call(self) if options[name].is_a?(Proc)
    end

    def batch_import
      batch_result = nil

      @resource.transaction do
        run_callback(:before_batch_import)
        batch_result = resource.import(@csv_rows.map{ |r| r.to_h.with_indifferent_access },
                                       import_options)
        raise ActiveRecord::Rollback if import_options[:batch_transaction] && batch_result.failed_instances.any?
        run_callback(:after_batch_import)
      end
      batch_result
    end

    def assign_options(options)
      @options = {
        batch_size: 1000,
        validate_uniqueness: true,
     }.merge(options.slice(*OPTIONS))
      detect_csv_options
    end

    def detect_csv_options
      # see active_admin_import/lib/active_admin_import/model.rb:8
      # for definition of :underscore - :downcase and :symbol are built in
      default_csv_options = {header_converters: [:underscore, :downcase, :symbol],
                             headers: true}

      given_csv_options = if model.respond_to?(:csv_options)
                            model.csv_options
                          else
                            options[:csv_options]
                          end
      @csv_options = default_csv_options.merge(given_csv_options).reject { |_, value| value.nil? || value == "" }
    end
  end
end
