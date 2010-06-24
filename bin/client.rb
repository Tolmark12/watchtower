#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../lib/metrics.rb'
require File.dirname(__FILE__) + '/../lib/daemon.rb'
require File.dirname(__FILE__) + '/../lib/parseconfig.rb'
require 'socket'

class WatchTowerClient < Daemon::Base
  WorkingDirectory = File.expand_path(File.dirname(__FILE__))  
  @log = STDOUT
  #static methods - this is really just a singleton though, so there are no instance methods
  class << self 
    def start
      conf = ParseConfig.new(WorkingDirectory + '/../etc/client.conf')
      metric = Metrics.new

      #read in configuration items
      interval = conf.params['interval'].to_i
      interval = 5 if interval == 0
      server_ip = conf.params['server_ip']
      server_port = conf.params['server_port']
      
      self.connect_to_server(server_ip, server_port)
      #Log client start
      loop do
        sleep interval
        self.send_message_to_server(metric.get_cpu_usage, metric.get_mem_usage, metric.get_load_average)
      end
    end
  
    def stop
      self.disconnect_from_server
    end
    
    def connect_to_server(server_ip, server_port)
      @socket = TCPSocket.open(server_ip,server_port)
      @socket.puts "info|1|123"
      @log.puts "===START=== #{server_ip}: #{server_port}"
      @log.flush
    end
    
    def send_message_to_server(cpu, mem, load)
      @socket.puts "data|#{cpu}|#{mem}|#{load}"
      @log.puts "to server - CPU = #{cpu}, Memory = #{mem}, Load = #{load}"
      @log.flush
    end
    
    def disconnect_from_server
      @socket.puts "stop"
      @socket.close
      @log.puts "===STOP==="
      @log.close
    end
  end
end

WatchTowerClient.daemonize
