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
      @interval = 1
      server_ip = conf.params['server_ip']
      server_port = conf.params['server_port']
      cluster = conf.params['cluster']
      
      self.connect_to_server(server_ip, server_port, cluster)
      sleep 0.5
      #Log client start
      loop do
#        sleep @interval - we're using time to be as exact as we can
        start = Time.now
        self.send_message_to_server(metric.get('cpu').to_f, metric.get('mem').to_f, metric.get('load'))
        newinterval = @interval - (Time.now - start)
        while newinterval <= 0
          @log.puts "Missed a beat by #{newinterval} seconds"
          newinterval += @interval
        end
        sleep (newinterval)
      end
    end
  
    def stop
      self.disconnect_from_server
    end
    
    def connect_to_server(server_ip, server_port, cluster)
      @socket = TCPSocket.open(server_ip,server_port)
      
      #listener listens to the server, can listen for certain messages
      @listener = Thread.new {
        while true
          line = @socket.gets
          
          # if line is empty that means that the server disconnected
          if !line
            @log.puts "Server went down"
            WatchTowerClient.kill_self
            break
          end
          line = line.split("|")
          type = line[0]
          line.shift
          
          if type == 'interval'
            @interval = line[0].to_i
            @log.puts "Got #{@interval} interval from server"
            @interval = 5 if @interval == 0
          else
            @log.puts "Message from server #{type} -- #{line}"
          end
        end
      }
      
      @socket.puts "info|#{cluster}"
      @log.puts "===START=== #{server_ip}: #{server_port}"
      @log.flush
    end
    
    def send_message_to_server(cpu, mem, load)
      @socket.puts "data|#{cpu}|#{mem}|#{load}"
      @log.puts "to server - CPU = #{cpu}, Memory = #{mem}, Load = #{load}"
      @log.flush
    end
    
    def disconnect_from_server
      @socket.close
      @log.puts "===STOP==="
      @log.close
    end
  end
end

WatchTowerClient.daemonize
