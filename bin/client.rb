require File.dirname(__FILE__) + '/../lib/metrics.rb'
require File.dirname(__FILE__) + '/../lib/daemon.rb'
require File.dirname(__FILE__) + '/../lib/parseconfig.rb'

class WatchTowerClient < Daemon::Base
  WorkingDirectory = File.expand_path(File.dirname(__FILE__))  
  
  #static methods
  class << self 
    def start
      conf = ParseConfig.new(WorkingDirectory + '/../etc/client.conf')
      metric = Metrics.new

      #read in configuration items
      interval = conf.params['interval'].to_i
      interval = 5 if interval == 0
      server_ip = conf.params['server_ip']
      server_port = conf.params['server_port']
    
      #Log client start
      @f = File.open('stats.log', 'a') 
      @f.puts "===START=== #{server_ip}: #{server_port}"
      @f.flush
    
      loop do
        sleep interval
        @f.puts "CPU: #{metric.get_cpu_usage}, Mem: #{metric.get_mem_usage}, Load: #{metric.get_load_average}"
        @f.flush
      end
    end
  
    def stop
      @f.puts "===STOP==="
      @f.close
    end
  end
  
  #instance methods go here
  
end

WatchTowerClient.daemonize
