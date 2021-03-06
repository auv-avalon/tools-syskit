module Syskit
    module Actions
        module Models
        # Representation of the deployment of a syskit instance requirement on
        # the action interface
        class Action < Roby::Actions::Models::Action
            # The instance requirement object for this action
            # @return [InstanceRequirements]
            attr_reader :requirements

            def initialize(action_interface_model, requirements, doc = nil)
                super(action_interface_model, doc)
                @requirements = requirements
                returns(requirements.proxy_task_model)
            end

            # @return [Action] an action instance based on this model
            def new(arguments = Hash.new)
                Actions::Action.new(self, arguments)
            end

            def plan_pattern(arguments = Hash.new)
                job_id, arguments = Kernel.filter_options arguments, :job_id
                req = requirements.dup
                req.with_arguments(arguments)
                placeholder = req.as_plan(job_id)
                placeholder.planning_task.action_model = self
                placeholder.planning_task.action_arguments = arguments
                placeholder
            end

            def to_instance_requirements
                new.to_instance_requirements
            end

            # Injects the tasks necessary to deploy #requirements on the plan
            # associated with the given action interface
            #
            # @param [ActionInterface] the action interface
            # @param [Hash] arguments the arguments (unused)
            # @return [Roby::Task] the action task
            def run(action_interface, arguments = Hash.new)
                action_interface.plan.add(task = plan_pattern(arguments))
                task
            end

            # Called by Roby::Actions::Models::Action to modify self so that it is
            # droby-marshallable
            #
            # It only resets the requirements attribute, as InstanceRequirements
            # are not (yet) marshallable in droby
            def droby_dump!(dest)
                super
                @requirements = Syskit::InstanceRequirements.new
            end

            def method_missing(m, *args, &block)
                if requirements.respond_to?(m)
                    req = requirements.dup
                    req.send(m, *args, &block)
                    Actions::Models::Action.new(action_interface_model, req, doc)
                else super
                end
            end
        end
        end
    end
end

