module Syskit
    # Namespace containing all the functionality required to integrate syskit in
    # a Roby application
    #
    # It is not loaded by default when you require 'syskit'. You need to
    # explicitly require 'syskit/roby_app'
    module RobyApp
    end
end

require 'syskit/roby_app/log_group'
require 'syskit/roby_app/robot_extension'
require 'syskit/roby_app/toplevel'
require 'syskit/roby_app/configuration'
require 'syskit/roby_app/plugin'


module Syskit
    class << self
        # The main configuration object
        #
        # For consistency reasons, it is also available as Roby.conf.syskit when
        # running in a Roby application
        attr_reader :conf
    end
    @conf = RobyApp::Configuration.new
end