module Syskit
    module Robot
        # RobotDefinition objects describe a robot through the devices that are
        # available on it.
        class RobotDefinition
            def initialize
                @devices    = Hash.new
            end

            # The devices that are available on this robot
            attr_reader :devices

            def clear
                devices.clear
            end

            # Declares a new communication bus
            def com_bus(type, options = Hash.new)
                device(type, options.merge(:expected_model => Syskit::ComBus, :class => ComBus))
            end

            # Returns true if +name+ is the name of a device registered on this
            # robot model
            def has_device?(name)
                devices.has_key?(name.to_str)
            end

            # Declares that all devices declared in the provided block are using
            # the given bus
            #
            # For instance:
            #
            #   through 'can0' do
            #       device 'motors'
            #   end
            #
            # is equivalent to
            #
            #   device('motors').
            #       attach_to('can0')
            #
            def through(com_bus, &block)
                if com_bus.respond_to?(:to_str)
                    bus = device[com_bus.to_str]
                    if !bus
                        raise ArgumentError, "communication bus #{com_bus} does not exist"
                    end
                end

                if !bus.respond_to?(:through)
                    raise ArgumentError, "#{bus} is not a communication bus"
                end
                bus.through(&block)
                bus
            end

            # Adds a new device to this robot definition.
            #
            # +device_model+ is either the device type or its name. It is
            # implicitely declared by the use of driver_for in component
            # classes, or by using SystemModel#device_type.
            #
            # For instance, if a Hokuyo orogen component is available that can
            # drive Hokuyo laser scanners, then one would declare the driver
            # with:
            #
            #   class Hokuyo
            #       driver_for 'Devices::Hokuyo'
            #   end
            #
            # the newly declared device type can then be accessed as a
            # constant with Devices::Hokuyo. I.e.
            #
            #   Devices::Hokuyo
            #
            # is the subclass of DeviceModel that describes this device type.
            # It can then be used to declare devices on a robot with
            #
            #   Robot.devices do
            #     device Devices::Hokuyo
            #   end
            #
            # This method returns the MasterDeviceInstance instance that
            # describes the actual device
            def device(device_model, options = Hash.new)
                options, device_options = Kernel.filter_options options,
                    :as => nil,
                    :using => nil,
                    :expected_model => Syskit::Device,
                    :class => MasterDeviceInstance
                device_options, task_arguments = Kernel.filter_options device_options,
                    MasterDeviceInstance::KNOWN_PARAMETERS

                # Check for duplicates
                if !options[:as]
                    raise ArgumentError, "no name given, please provide the :as option"
                end
                name = options[:as]
                if devices[name]
                    raise ArgumentError, "device #{name} is already defined"
                end

                # Verify that the provided device model matches what we expect
                if !(device_model < options[:expected_model])
                    raise ArgumentError, "#{device_model} is not a #{options[:expected_model].short_name}"
                end

                # If the user gave us an explicit selection, honor it
                driver_model = options[:using]
                if !driver_model
                    # Since we want to drive a particular device, we actually need a
                    # concrete task model. So, search for one.
                    #
                    # Get all task models that implement this device
                    tasks = TaskContext.submodels.
                        find_all { |t| t.fullfills?(device_model) }

                    # Now, get the most abstract ones
                    tasks.delete_if do |model|
                        tasks.any? { |t| model < t }
                    end

                    if tasks.size > 1
                        raise Ambiguous, "#{tasks.map(&:short_name).join(", ")} can all handle '#{device_model.short_name}', please select one explicitely with the 'using' statement"
                    elsif tasks.empty?
                        raise ArgumentError, "no task can handle devices of type '#{device_model.short_name}'"
                    end
                    driver_model = tasks.first
                end

                if driver_model.respond_to?(:find_data_service_from_type)
                    driver_model = driver_model.find_data_service_from_type(device_model)
                end

                root_task_arguments = { "#{driver_model.name}_name" => name }.
                    merge(task_arguments)

                device_instance = options[:class].new(
                    self, name, device_model, device_options,
                    driver_model, root_task_arguments)
                devices[name] = device_instance
                device_model.apply_device_configuration_extensions(devices[name])

                # And register all the slave services there is on the driver
                driver_model.each_slave_data_service do |slave_service|
                    slave_device = SlaveDeviceInstance.new(devices[name], slave_service)
                    device_instance.slaves[slave_service.name] = slave_device
                    devices["#{name}.#{slave_service.name}"] = slave_device
                end

                device_instance
            end

            def each_device(&block)
                devices.each(&block)
            end

            # Enumerates all master devices that are available on this robot
            def each_master_device
                devices.find_all { |name, instance| instance.kind_of?(MasterDeviceInstance) }.
                    each { |_, instance| yield(instance) }
            end

            # Enumerates all slave devices that are available on this robot
            def each_slave_device
                devices.find_all { |name, instance| instance.kind_of?(SlaveDeviceInstance) }.
                    each { |_, instance| yield(instance) }
            end

            def method_missing(m, *args, &block)
                if args.empty? && !block_given?
                    if dev = devices[m.to_s]
                        return dev
                    end
                end

                super
            end
        end
    end
end
