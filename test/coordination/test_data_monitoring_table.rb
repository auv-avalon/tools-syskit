require 'syskit/test'

describe Syskit::Coordination::DataMonitoringTable do
    include Syskit::SelfTest

    attr_reader :component_m, :table_m
    before do
        @component_m = Syskit::TaskContext.new_submodel { output_port 'out', '/int' }
        @table_m = Syskit::Coordination::DataMonitoringTable.
            new_submodel(:root => component_m)
    end

    it "generates an error if one of its monitor has no trigger" do
        table_m.monitor('sample_value_10', table_m.out_port)
        root_task = syskit_deploy_and_start_task_context(component_m, 'task')
        assert_raises(Syskit::Coordination::Models::InvalidDataMonitor) { table_m.new(root_task) }
    end

    it "generates an error if one of its monitor has no effect" do
        table_m.monitor('sample_value_10', table_m.out_port).
            trigger_on { |sample| }
        root_task = syskit_deploy_and_start_task_context(component_m, 'task')
        assert_raises(Syskit::Coordination::Models::InvalidDataMonitor) { table_m.new(root_task) }
    end

    it "should raise if some monitors have no effect at the end of the definition block" do
        assert_raises(Syskit::Coordination::Models::InvalidDataMonitor) do
            Syskit::Coordination::DataMonitoringTable.new_submodel(:root => component_m) do
                monitor 'test', out_port do
                end
            end
        end
    end

    it "generates a CodeError if the trigger raises" do
        recorder = flexmock
        table_m.monitor('test', table_m.out_port).
            trigger_on { |sample| raise }.
            raise_exception

        component = syskit_deploy_task_context(component_m, 'task')
        table = table_m.new(component)
        syskit_start_component(component)
        component.orocos_task.out.write(10)
        inhibit_fatal_messages do
            process_events
        end
        assert_kind_of Roby::CodeError, component.failure_reason
    end

    it "gives access to the monitoring table arguments as local variables in the blocks" do
        recorder = flexmock
        table_m.argument :arg
        table_m.monitor('test', table_m.out_port).
            trigger_on do |sample|
                recorder.called(arg)
                false
            end.raise_exception

        component = syskit_deploy_task_context(component_m, 'task')
        table = table_m.new(component, :arg => 10)
        recorder.should_receive(:called).with(10).at_least.once
        syskit_start_component(component)
        component.orocos_task.out.write(20)
        process_events
    end

    it "allows to store state using local variables" do
        recorder = flexmock
        table_m.argument :arg
        table_m.monitor('test', table_m.out_port).
            trigger_on do |sample|
                @value = !@value
                recorder.called(@value)
                false
            end.raise_exception

        component = syskit_deploy_task_context(component_m, 'task')
        table = table_m.new(component, :arg => 10)
        recorder.should_receive(:called).with(true).at_least.once
        recorder.should_receive(:called).with(false).at_least.once
        syskit_start_component(component)
        component.orocos_task.out.write(20)
        process_events
        component.orocos_task.out.write(20)
        process_events
    end

    it "can attach to a component and trigger an error when the condition is met" do
        component_m = Syskit::TaskContext.new_submodel do
            output_port 'out1', '/int'
            output_port 'out2', '/int'
        end
        table_m = Syskit::Coordination::DataMonitoringTable.
            new_submodel(:root => component_m)
        recorder = flexmock
        table_m.monitor('sample_value_10', table_m.out1_port, table_m.out2_port).
            trigger_on do |sample1, sample2|
                recorder.called(sample1, sample2)
                sample1 + sample2 > 10
            end.
            emit(table_m.success_event).
            raise_exception

        recorder.should_receive(:called).with(5, 2).once.ordered
        recorder.should_receive(:called).with(5, 7).once.ordered

        component = syskit_deploy_and_start_task_context(component_m, 'task')
        table = table_m.new(component)
        process_events
        component.orocos_task.out1.write(5)
        component.orocos_task.out2.write(2)
        table.poll
        component.orocos_task.out2.write(7)
        assert_raises(Syskit::Coordination::DataMonitoringError) do
            inhibit_fatal_messages do
                table.poll
            end
        end
        assert component.success?
    end
    it "can monitor the child of a composition, and applies port mappings" do
        srv_m = Syskit::DataService.new_submodel(:name => 'Srv') { output_port 'out', '/int' }
        composition_m = Syskit::Composition.new_submodel(:name => 'Cmp') { add srv_m, :as => 'test' }
        component_m = Syskit::TaskContext.new_submodel(:name => 'Task') do
            output_port 'out1', '/int'
            output_port 'out2', '/int'
            provides srv_m, :as => 'test1', 'out' => 'out1'
            provides srv_m, :as => 'test2', 'out' => 'out2'
        end
        table_m = Syskit::Coordination::DataMonitoringTable.
            new_submodel(:root => composition_m)
        recorder = flexmock
        table_m.monitor('sample_value_10', table_m.test_child.out_port).
            raise_exception.
            emit(table_m.test_child.success_event).
            trigger_on do |sample|
                recorder.called(sample)
                sample > 10
            end

        recorder.should_receive(:called).with(2).once.ordered
        recorder.should_receive(:called).with(12).once.ordered

        component = syskit_deploy_and_start_task_context(component_m, 'task')
        composition = composition_m.use('test' => component.test2_srv).instanciate(plan)
        composition.depends_on composition.test_child, :success => :success, :remove_when_done => true
        plan.add_permanent(composition)

        table = table_m.new(composition)
        process_events
        process_events
        component = composition.test_child
        component.orocos_task.out1.write(2)
        component.orocos_task.out2.write(2)
        table.poll
        component.orocos_task.out1.write(1)
        component.orocos_task.out2.write(12)
        assert_raises(Syskit::Coordination::DataMonitoringError) do
            inhibit_fatal_messages do
                table.poll
            end
        end
        assert component.success?
        composition.emit :success
    end

    it "can use whole component networks as data sources" do
        srv_m = Syskit::DataService.new_submodel(:name => 'Srv') { output_port 'out', '/int' }
        composition_m = Syskit::Composition.new_submodel(:name => 'Cmp') do
            add srv_m, :as => 'test'
            export test_child.out_port
        end
        component_m = Syskit::TaskContext.new_submodel(:name => 'Task') do
            output_port 'out1', '/int'
            output_port 'out2', '/int'
            provides srv_m, :as => 'test1', 'out' => 'out1'
            provides srv_m, :as => 'test2', 'out' => 'out2'
        end
        table_m = Syskit::Coordination::DataMonitoringTable.
            new_submodel(:root => composition_m)
        recorder = flexmock
        monitor_task = table_m.task(composition_m.use('test' => component_m.test2_srv))
        table_m.monitor('sample_value_10', table_m.out_port, monitor_task.out_port).
            trigger_on do |sample1, sample2|
                recorder.called(sample1, sample2)
                sample1 + sample2 > 10
            end.
            emit(table_m.success_event).
            raise_exception

        recorder.should_receive(:called).with(4, 2).once.ordered
        recorder.should_receive(:called).with(1, 12).once.ordered

        component = syskit_deploy_task_context(component_m)
        plan.add_permanent(composition = composition_m.use('test' => component.test1_srv).instanciate(plan))
        syskit_start_component(composition)
        table = table_m.new(composition)
        process_events
        Syskit::Runtime.apply_requirement_modifications(plan)

        monitor     = (plan.find_tasks(composition_m).to_a - [composition]).first
        # We want the fault table to emit 'success', don't make it an error
        composition.depends_on composition.test_child,
            :success => :success, :remove_when_done => true

        component = composition.test_child
        component.orocos_task.out1.write(4)
        component.orocos_task.out2.write(2)
        table.poll
        component.orocos_task.out1.write(1)
        component.orocos_task.out2.write(12)
        assert_raises(Syskit::Coordination::DataMonitoringError) do
            inhibit_fatal_messages do
                table.poll
            end
        end
        assert composition.success?
    end

    describe "#remove!" do
        it "allows to untie the table from the task" do
            recorder = flexmock
            table_m.monitor('test', table_m.out_port).
                trigger_on { |sample| true }.
                emit table_m.success_event

            component = syskit_deploy_task_context(component_m, 'task')
            table = table_m.new(component)
            syskit_start_component(component)
            table.remove!
            component.orocos_task.out.write(10)
            process_events
            assert !component.finished?
        end
    end

    describe "transactions" do
        before do
            table_m.argument :arg
        end
        it "can be added in a transaction" do
            flexmock(plan).should_receive(:use_data_monitoring_table).with(table_m, :arg => 10).once
            plan.in_transaction do |trsc|
                trsc.use_data_monitoring_table table_m, :arg => 10
                trsc.commit_transaction
            end
        end
        it "is not added if the transaction is discarded" do
            flexmock(plan).should_receive(:use_data_monitoring_table).never
            plan.in_transaction do |trsc|
                trsc.use_data_monitoring_table table_m, :arg => 10
                trsc.discard_transaction
            end
        end
        it "is added only once if added to the transaction through a fault response table" do
            fault_table_m = Roby::Coordination::FaultResponseTable.new_submodel
            fault_table_m.use_data_monitoring_table table_m, :arg => 10
            flexmock(plan).should_receive(:use_data_monitoring_table).with(table_m, :arg => 10).once
            plan.in_transaction do |trsc|
                trsc.use_fault_response_table fault_table_m
                trsc.commit_transaction
            end
        end
    end
end

