require 'yaml'

module Resque
  module Plugins
    module Resqued
      class Manager
        attr_reader :options, :delay, :worker_groups

        def initialize(options = {})
          @options = options
          @worker_groups = {}

          config = load_config_file(options[:config]) if options[:config]
        end

        def run!
          manage!
          # sleep delay
          # run!
        end

        def manage!
          worker_groups.each_value { |wg| wg.manage! }
        end

        private

        def load_config_file(config)
          @config_file ||= Yambol.load_file(config)
          if @config_file
            set_delay(@config_file[:delay])
            set_worker_groups(@config_file[:workers])
          end
        end

        def set_delay(delay)
          @delay = delay
        end

        def set_worker_groups(groups)
          groups.each do |name, options|
            @worker_groups[name] = WorkerGroup.new(name, options.merge(manager: self))
          end
        end
      end
    end
  end
end

