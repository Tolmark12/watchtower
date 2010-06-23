require File.dirname(__FILE__) + '/../lib/daemon.rb'
require File.dirname(__FILE__) + '/../lib/parseconfig.rb'

class WatchTowerServer < Daemon::Base
  WorkingDirectory = File.expand_path(File.dirname(__FILE__))  
  #static methods
  class << self
    def start
    end
    
    def stop
    end
  end

  #instance methods go here
end

WatchTowerClient.daemonize