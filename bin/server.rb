#!/usr/bin/env ruby
require File.dirname(__FILE__) + '/../lib/daemon.rb'
require File.dirname(__FILE__) + '/../lib/parseconfig.rb'
require File.dirname(__FILE__) + '/../lib/rules.rb'
require File.dirname(__FILE__) + '/../lib/actions.rb'
require File.dirname(__FILE__) + '/../lib/max_queue.rb' #overwrite array to have max_size and push_safe
require 'socket'
require 'thread'

# Boilerplate to allow custom ruby functionality if they are able
require File.dirname(__FILE__) + '/init.rb' if File.exists? File.dirname(__FILE__) + '/init.rb'

class WatchTowerServer < Daemon::Base
  WorkingDirectory = File.expand_path(File.dirname(__FILE__))  
  @data = Array.new
  @data_lock = Mutex.new
  @listener_lock = Mutex.new
  @rules_lock = Mutex.new
  @averages = Array.new
  @cluster_map = Hash.new
  #static methods
  class << self
    attr_accessor :data, :averages
    
    def server_interval
      @data_lock.lock
      @last = @latest
      @latest = Hash.new
      @averages.push_safe(average_data(@last))
      @data.push_safe(@latest) #if @last.size > 0
      @data_lock.unlock
      
      #for each cluster
      @averages[0].keys.each do |cluster|
        #check to see if u decrement check in it reaches 0 (returns 1 for true)
        @rules.each do |rule|
          if (rule.decrement_check_in == true)
            @rules_lock
              #check the rule, which will fire it on Actions if it's met
              rule.check_rule(@averages, cluster)
            @rules_unlock
          end
        end
      end
    end
    
    def average_data(last)
      clusters = Hash.new
      last.each do |clustername, cluster|
        metric_names = cluster[cluster.keys[0]].keys
        average_metrics = Hash.new
        metric_names.each do |metric_name|
          total_metric_value = 0
          cluster.each do |hostname, client|
            total_metric_value += client[metric_name].to_f
          end
          average_metrics[metric_name] = total_metric_value / cluster.size
          @log.puts("average #{metric_name} of #{cluster.size}: #{average_metrics[metric_name]}")
          @log.flush
        end
        clusters[clustername] = average_metrics
      end
      return clusters
    end

    def handle_client(socket)
      while true
        input = socket.gets

        if !input
          break
        end

        input.chop!
        #     on data - split on |
        input = input.split("|")
        type = input[0]
        input.shift
        case type
        when "data"
          @data_lock.lock
          @latest[@cluster_map[socket.peeraddr[2]]] ||= Hash.new
          @latest[@cluster_map[socket.peeraddr[2]]][socket.peeraddr[2]] = Hash.new
          @latest[@cluster_map[socket.peeraddr[2]]][socket.peeraddr[2]]['cpu'] = input[0]
          @latest[@cluster_map[socket.peeraddr[2]]][socket.peeraddr[2]]['mem'] = input[1]
          @latest[@cluster_map[socket.peeraddr[2]]][socket.peeraddr[2]]['load'] = input[2].split(" ")[0]              
          @data_lock.unlock
          @log.puts "I got #{input.join('|')} from #{@cluster_map[socket.peeraddr[2]]}-#{socket.peeraddr[2]} #{@data.size}"
        when "info"
          @log.puts "I got #{input[0]} from #{socket.peeraddr[2]}"
          @log.flush
          if (input[0] == nil || input[0] == "")
            input[0] = "default"
          end

          @log.puts "@cluster_map[#{socket.peeraddr[2]} = #{input[0]}]"
          @cluster_map[socket.peeraddr[2]] = input[0]
          @log.puts "I got info from #{socket.peeraddr[2]}"
        end
      end
      
      #after the client disconnects
      @log.puts "Client on #{socket.peeraddr[2]} disconnected."
      @listener_lock.lock
        @sockets.delete(socket)
      @listener_lock.unlock
      socket.close
    end
    
    def start
      @averages.max_size = 100
      @data.max_size = 100
      
      conf = ParseConfig.new(WorkingDirectory + '/../etc/server.conf')
      @rules = Rule.read_in_rules(WorkingDirectory + '/../etc/rules.conf')
      port = conf.params['server_port']
      @interval = conf.params['interval'].to_i
      @interval = 5 if @interval == 0

      max_size = conf.params['max_size'].to_i
      if (max_size == 0)
        max_size = 100
      end
      
      @listener = TCPServer.open(port)
      @sockets = []
      @log = STDOUT
      log = STDOUT
      
      #spawn a thread to run on an interval
      @latest = Hash.new
      @server_interval_thread = Thread.new {
        sleep @interval
        while true
          start = Time.now
          if @sockets.size > 0
            server_interval()
          end
          newinterval = @interval - (Time.now - start)
          while newinterval <= 0
            @log.puts "Missed a beat by #{newinterval} seconds"
            newinterval += @interval
          end
          sleep (newinterval)
        end
      }
      
      # listen for connections
      while true
        client = @listener.accept
        Thread.start(client) do |c|
          @listener_lock.lock
          @sockets << c
          @listener_lock.unlock
          c.puts "interval|#{@interval}"
          handle_client(c)
          log.puts "Accepted connection from #{client.peeraddr[2]} I sent them interval|#{@interval}"
        end
      end        
    end
    
    def stop
      @listener.close #doing this will automatically close all the sockets
    end
  end

  #instance methods go here
end

WatchTowerServer.daemonize