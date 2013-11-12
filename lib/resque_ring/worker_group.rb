module Resque
  module Plugins
    module ResqueRing
      class WorkerGroup
        extend HattrAccessor

        # @return [String] name of the WorkerGroup
        attr_reader :name

        # @return [Manager] {Manager} class for this WorkerGroup
        attr_reader :manager

        # @return [Hash{String => Queue}] a hash containing
        #   the {Queue} instances managed by this
        #   WorkerGroup, organized by name
        attr_reader :queues

        # @!method spawn_rate
        #   @return [Object] How many new workers to spawn at a time.
        #     Defaults to 1
        hattr_reader :options, :spawn_rate

        # @!method threshold
        #   @return [Object] the number of queue items
        #     needed before spawning more workers. Defaults to 100
        hattr_reader :options, :threshold

        # @!method wait_time
        #   @return [Object] How long to wait after spawning before
        #     spawning a new worker. Should be longer than the global
        #     delay. Defaults to 60
        hattr_reader :options, :wait_time

        # @!method remove_when_idle
        #   @return [Boolean] whether or not to reduce
        #     worker capacity when idle. Defaults to false
        hattr_reader :options, :remove_when_idle

        # @param name [String] a name for this WorkerGroup
        # @param options [Hash] options for this WorkerGroup
        def initialize(name, options = {})
          @name = name.to_s
          @manager = options.delete(:manager)

          build_queues(options.fetch(:queues, []))
          @options = defaults.merge(options)
        end

        # A list of environment variables used when
        # spawning a {Worker Worker}
        # @return [Hash] ENV variable names & values
        def environment
          @env ||= @options[:spawner][:env]
        end

        # Instructs a {Pool} to manage its workers
        def manage!
          pool.manage!
        end

        # @return [Pool] the pool of workers for this WorkerGroup
        def pool
          @pool ||= Resque::Plugins::ResqueRing::Pool.new(@options[:pool].merge(worker_group: self))
        end

        # @return [Boolean] true if all associated queues are empty
        def queues_are_empty?
          queues_total == 0
        end

        # @return [Integer] sum of sizes of all associated queues
        def queues_total
          queues.values.map(&:size).reduce(:+)
        end

        # @return [Registry] the {Registry} associated with this
        #   WorkerGroup's {Manager}
        def registry
          manager.registry
        end

        # @return [Array] an array of strings for building the
        #   spawning command
        def spawn_command
          @spawn_command ||= @options[:spawner][:command]
        end

        # collects an [Array] of spawn command elements
        # while replacing a placeholder with a list
        # of associated {Queue Queues} concatenated into
        # a String
        # @return [Array] an array of strings used by
        #   the {Pool} when spawning a {Worker}
        def spawner
          spawn_command.collect { |c| c.gsub('{{queues}}', "QUEUES=#{queues.map(&:to_s).join(',')}") }
        end

        # @return [Boolean] true if total items in all queues
        #   is greater than {#threshold} and the {Pool} is
        #   ready to spawn a new worker
        def wants_to_add_workers?
          queues_total >= threshold && pool.able_to_spawn?
        end

        # @return [Boolean] true if all queues are empty
        #   and {#remove_when_idle} returns true
        def wants_to_remove_workers?
          remove_when_idle && queues_are_empty?
        end

        # @return [String] the working directory for
        #   the spawner command
        def work_dir
          @work_dir ||= @options[:spawner][:dir]
        end

        # @return [Hash] options for the {Worker} that
        #   {Pool} will spin up on request
        def worker_options
          { spawner: spawner, env: environment, cwd: work_dir }
        end

        private

        def build_queues(queues)
          @queues ||= {}

          return if queues.nil?
          queues.each do |q|
            @queues.store(q, Queue.new(name: q, worker_group: self))
          end
        end

        def defaults
          {
            spawn_rate:       1,
            threshold:        100,
            wait_time:        60,
            remove_when_idle: false,
            pool:             {}
          }
        end
      end
    end
  end
end