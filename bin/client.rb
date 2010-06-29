#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../lib/daemon.rb'
require File.dirname(__FILE__) + '/../lib/parseconfig.rb'
require 'socket'

class WatchTowerClient < Daemon::Base
  WorkingDirectory = File.expand_path(File.dirname(__FILE__))  
  @log = STDOUT
  @metrics = Array.new
  #static methods - this is really just a singleton though, so there are no instance methods
  class << self 
    def start
      conf = ParseConfig.new(WorkingDirectory + '/../etc/client.conf')
#      metric = Metrics.new
      #read in configuration items
      @interval = 1
      server_ip = conf.params['server_ip']
      server_port = conf.params['server_port']
      cluster = conf.params['cluster']
      client_type = conf.params['client_type']
      self.connect_to_server(server_ip, server_port, cluster, client_type)
      sleep 0.5
      #Log client start
      loop do
#        sleep @interval - we're using time to be as exact as we can
        start = Time.now
        if @metrics.size > 0
          response = ["data"]
          @metrics.each do |metric_string|
            cmd = %x[#{metric_string}]
            response << cmd.to_f
          end
          @socket.puts(response.join("|"))
          @log.puts response.join("|")
        else
          @log.puts "I don't know which metrics to use yet"
        end
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
    
    def connect_to_server(server_ip, server_port, cluster,client_type)
      @socket = TCPSocket.open(server_ip,server_port)
      @socket.puts "info|#{cluster}|#{client_type}"
      @log.puts "===START=== #{server_ip}: #{server_port}"
      @log.flush
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
          line = line.split("-$-")
          type = line[0]
          line.shift
          
          if type == 'info'
            @interval = line[0].to_i
            @metrics = line[1].split("-$$-")
            @log.puts "Got #{@interval} interval from server"
            @log.puts "Got #{@metrics.join("/")} from server"
            @interval = 5 if @interval == 0
          else
            @log.puts "Message from server #{type} -- #{line}"
          end
        end
      }
      
    end
    
    def disconnect_from_server
      @socket.close
      @log.puts "===STOP==="
      @log.close
    end
  end
end

WatchTowerClient.daemonize
