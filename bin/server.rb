#!/usr/bin/env ruby
require File.dirname(__FILE__) + '/../lib/daemon.rb'
require File.dirname(__FILE__) + '/../lib/parseconfig.rb'
require File.dirname(__FILE__) + '/../lib/rules.rb'
require File.dirname(__FILE__) + '/../lib/metrics.rb'
require File.dirname(__FILE__) + '/../lib/max_queue.rb' #overwrite array to have max_size and push_safe
require 'socket'
require 'thread'

# Boilerplate to allow custom ruby functionality if they are able
require File.dirname(__FILE__) + '/init.rb' if File.exists? File.dirname(__FILE__) + '/init.rb'

module WatchTower
  # Cluster, Server, and Rules
  class Cluster

    def initialize(name)
      @data_lock = Mutex.new
      @rules_lock = Mutex.new
      @clients = []
      @latest = Hash.new
      @name = name
      @rules, @metrics = Rule.get_rules_for_cluster(name)
      @data = Array.new
      @data.max_size = Server.max_size
      @averages = Array.new
      @averages.max_size = Server.max_size
      puts "Cluster #{name} is initialized"
    end
    
    def add_client(socket, group_name)
      #create a thread that listens and responds to the client
      @clients << socket
      metric_lines = get_metrics_for_client(group_name)
      puts "There are #{@metrics.size} metrics"
      if metric_lines.size > 0
        socket.puts "info-$-#{Server.interval}-$-#{metric_lines.join("-$$-")}"
        puts "Sending #{metric_lines.join('\/')}"
      else
        socket.puts "error-$-There are no rules setup yet for your cluster"
        puts "Error, no metrics found for #{@name}, #{group_name}"
      end

      Thread.new do
        while true
          input = socket.gets

          if !input
            break
          end

          input.chop!
          input = input.split("|")
          type = input[0]
          input.shift

          if type != "data"
            puts "Invalid data from client: #{type} != data"
          else
            @data_lock.lock
            @latest[socket.peeraddr[2]] = Hash.new
            i = 0
            @metrics.each do |metric|
              @latest[socket.peeraddr[2]][metric] = input[i]
              i = i + 1
            end
            @data_lock.unlock

            puts "#{@name}-#{socket.peeraddr[2]} -- #{input.join('|')}"
          end
        end
        puts "Client on #{socket.peeraddr[2]} disconnected from cluster #{@name}."
        @clients.delete(socket)
        socket.close
      end
    end

    def get_metrics_for_client(group)
      metric_lines = []
      @metrics.each do |metric|
        if group != ""
          metric_lines << Server.metrics.params[group][metric]
        else
          metric_lines << Server.metrics.params[metric]
        end
      end
      return metric_lines
    end
    
    def on_server_interval
      @data_lock.lock
      @last = @latest
      @latest = Hash.new
      average = average_data(@last)
      if average.size > 0
        @averages.push_safe(average)
      end
#      @data.push_safe(@latest) #if @last.size > 0
      @data_lock.unlock

      #check to see if u decrement check in it reaches 0 (returns 1 for true)
      @rules.each do |rule|
        if (rule.decrement_check_in == true)
          @rules_lock.lock
            #check the rule, which will fire it on Actions if it's met
            rule.check_rule(@averages)
          @rules_lock.unlock
        end
      end
    end
    
    def average_data(last)
      average = Hash.new
      string = "average "
      size = 0
      @metrics.each do |metric_name|
        total_metric_value = 0
        last.each do |hostname, client|
          total_metric_value += client[metric_name].to_f
        end
        average[metric_name] = total_metric_value / last.size
        string = string + "#{metric_name}: #{average[metric_name]}, "
        size = last.size
        puts "#{@name}: #{string} with #{size} clients"
      end
      return average
    end
  end
  
  class Server < Daemon::Base
    WorkingDirectory = File.expand_path(File.dirname(__FILE__))  
    @@clusters = Hash.new
    #static methods
    class << self
      attr_reader :metrics, :interval, :max_size
      def initialize
        @listener_lock = Mutex.new
      end

      def start_server_interval
        @server_interval_thread = Thread.new {
          sleep @interval
          while true
              start = Time.now
            @@clusters.each do |clustername, cluster|
              cluster.on_server_interval
            end
            new_interval = @interval - (Time.now - start)
            while new_interval <= 0
              puts "Missed a beat by #{new_interval} seconds"
              new_interval += @interval
            end
            sleep(new_interval)
          end
        }
      end

      def listen_for_connections
        while true
          client = @listener.accept
          Thread.start(client) do |c|
            input = c.gets

            if !input
              break
            end

            input.chop!
            input = input.split("|")
            type = input[0]
            input.shift

            if type != "info"
              puts "ERROR- the client isn't speaking my language - he said #{type} rather than giving me info"
            else
              input[0] ||= "default"
              input[0] = "default" if input[0] == ""
              if @@clusters.include?(input[0]) == false
                puts "Creating cluster #{input[0]}"
                @@clusters[input[0]] = Cluster.new(input[0])
              else
                puts "Clusters already has #{input[0]}"
              end

              @@clusters[input[0]].add_client(c, input[1])
              puts "Accepted connection from #{c.peeraddr[2]} I sent them to cluster #{input[0]}"
            end
          end
        end
      end

      def start
        #set the file for Rule to use
        Rule.setup_rules(WorkingDirectory + '/../etc/rules.conf')

        # Read in the config file and setup config variables
        conf = ParseConfig.new(WorkingDirectory + '/../etc/server.conf')
        @metrics = ParseConfig.new(WorkingDirectory + '/../etc/metrics.conf')
        port = conf.params['server_port']
        @interval = conf.params['interval'].to_i
        @interval = 5 if @interval == 0

        @max_size = conf.params['max_size'].to_i
        if (@max_size == 0)
          @max_size = 100
        end
      
        @listener = TCPServer.open(port)

        #spawn a thread to run on an interval
        @latest = Hash.new

        start_server_interval #starts up a thread that loops forever
        listen_for_connections #this runs forever (making this a daemon)
      end
    
      def stop
        @listener.close #doing this will automatically close all the sockets
      end
    end
  end
end
Thread.abort_on_exception = true
WatchTower::Server.daemonize