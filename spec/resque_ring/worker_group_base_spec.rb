require 'spec_helper'
require './spec/support/hash_queue_store'

describe ResqueRing::WorkerGroup do
  let(:mgr) { ResqueRing::Manager.new({}) }
  let(:options) { Hash.new.merge(manager: mgr) }
  subject { ResqueRing::WorkerGroup.new('indexing', options) }

  it 'stores a reference to its manager' do
    subject.manager.must_equal mgr
  end

  context 'queues' do
    let(:store) { HashQueueStore.new }
    let(:wg) { ResqueRing::WorkerGroup.new('indexing', options) }
    let(:queue_a) { ResqueRing::Queue.new(name: 'queue_a', worker_group: wg, store: store) }
    let(:queue_b) { ResqueRing::Queue.new(name: 'queue_b', worker_group: wg, store: store) }

    before do
      store.queues['queue_a'] = 1
      store.queues['queue_b'] = 3

      wg.instance_variable_set('@queues', { 'queue_a' => queue_a, 'queue_b' => queue_b })
    end

    subject { wg }

    it 'can get the number of jobs in a single queue' do
      subject.queues['queue_a'].size.must_equal(1)
    end

    it 'can get the total jobs in all watched queues' do
      subject.queues_total.must_equal(4)
    end
  end

  context 'with no provided configuration' do
    it 'defaults to a wait_time of 60' do
      subject.wait_time.must_equal 60
    end

    it 'defaults to a queue threshold of 100' do
      subject.threshold.must_equal 100
    end

    it 'defaults to a spawn_rate of 1' do
      subject.spawn_rate.must_equal 1
    end

    it 'defaults to no watched queues' do
      subject.queues.must_equal({})
    end

    it 'creates a Pool' do
      subject.pool.class.must_equal ResqueRing::Pool
    end
  end

  context 'with a provided configuration' do
    let(:options) { file = Yambol.load_file('./spec/support/config_with_delay.yml')[:workers][:indexing] }
    let(:wg) { ResqueRing::WorkerGroup.new('indexing', options.merge(manager: mgr)) }
    subject { wg }

    it 'knows its spawn command' do
      subject.spawn_command.must_equal options[:spawner][:command]
    end

    it 'knows its work dir' do
      subject.work_dir.must_equal options[:spawner][:dir]
    end

    it 'knows its environment variables' do
      subject.environment.must_equal options[:spawner][:env]
    end

    it 'sets proper wait_time' do
      subject.wait_time.must_equal options[:wait_time]
    end

    it 'sets proper queue threshold' do
      subject.threshold.must_equal options[:threshold]
    end

    it 'sets proper spawn_rate' do
      subject.spawn_rate.must_equal options[:spawn_rate]
    end

    it 'has three watched queues' do
      subject.queues.size.must_equal options[:queues].size
    end

    it 'includes the proper queues' do
      subject.queues.keys.must_equal options[:queues]
    end

    it 'creates a Pool' do
      subject.pool.must_be_instance_of ResqueRing::Pool
    end

    context 'when #manage! is called' do
      let(:pool) { MiniTest::Mock.new }

      before do
        wg.instance_variable_set(:@pool, pool)
        pool.expect(:manage!, true)
      end

      it 'tells its pool to manage itself' do
        wg.manage!
      end

      after { pool.verify }
    end

    context '#queues_are_empty?' do
      context 'if all queues have no items' do
        before { wg.stubs(:queues_total).returns(0) }

        it 'returns true' do
          wg.queues_are_empty?.must_equal(true)
        end

        after { wg.unstub(:queues_total) }
      end
    end

    context '#wants_to_add_workers?' do
      subject { wg.wants_to_add_workers? }

      context 'when queues_total greater than threshold' do
        before do
          wg.stubs(:queues_total).returns(100)
          wg.stubs(:threshold).returns(50)
        end

        context 'pool is able to spawn' do
          before do
            wg.pool.expects(:able_to_spawn?).returns(true)
          end

          it 'returns true' do
            subject.must_equal(true)
          end

          after { wg.pool.unstub(:able_to_spawn?) }
        end

        context 'pool is unable to spawn' do
          before do
            wg.pool.expects(:able_to_spawn?).returns(false)
          end

          it 'returns false' do
            subject.must_equal(false)
          end

          after { wg.pool.unstub(:able_to_spawn?) }
        end

        after { wg.unstub }
      end

      context 'when queues_total less than threshold' do
        it 'returns false' do
          subject.must_equal(false)
        end
      end
    end

    context '#wants_to_remove_workers?' do
      subject { wg.wants_to_remove_workers? }

      context 'when remove_when_idle is true' do
        before { wg.expects(:remove_when_idle).returns(true) }

        context 'when queues are empty' do
          before { wg.expects(:queues_total).returns(0)}

          it 'returns true' do
            subject.must_equal(true)
          end

          after { wg.unstub(:queues_total) }
        end

        context 'when queues are not empty' do
          before { wg.expects(:queues_total).returns(10) }

          it 'returns false' do
            subject.must_equal(false)
          end

          after { wg.unstub(:queues_total) }
        end

        after { wg.unstub(:remove_when_idle) }
      end

      context 'when remove_when_idle is false' do
        before { wg.expects(:remove_when_idle).returns(false) }

        it 'returns false' do
          subject.must_equal(false)
        end

        after { wg.unstub(:remove_when_idle) }
      end
    end

    context '#worker_options' do
      subject { wg.worker_options }

      it 'includes the proper keys' do
        subject.keys.must_equal [:spawner, :env, :cwd]
      end

      it 'includes a spawner' do
        subject[:spawner].must_equal wg.spawner
      end

      it 'includes env' do
        subject[:env].must_equal wg.environment
      end

      it 'includes cwd' do
        subject[:cwd].must_equal wg.work_dir
      end
    end

    context '#spawner' do
      context 'if command includes {{queues}}' do
        it 'returns spawn command with queues inserted' do
          subject.spawner.must_equal options[:spawner][:command].each { |c| c.gsub!("{{queues}}", "QUEUES=#{subject.queues.map(&:to_s).join(',')}") }
        end
      end
    end
  end
end
