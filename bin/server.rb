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
  class Node
    attr_accessor :socket, :group_name, :health_this_go, :wait_for
    
    def initialize(socket, group_name)
      @socket = socket
      @group_name = group_name
      @health_this_go = 0
      @health_failures = 0
      @wait_for = 0
      log = STDOUT
      puts("This is a test")
    end

    def send(string)
      @socket.puts(string)
    end

    def get_name
      return @socket.peeraddr[2]
    end

    def gets
      return @socket.gets
    end

    def check
      if @health_this_go == 0
        @health_failures = @health_failures + 1
      else
        @health_failures = 0
      end
      puts "My wait_for = #{@wait_for}, my health failures = #{@health_failures}, and my health_this_go = #{@health_this_go}"
      @health_this_go = 0 #reset health this go
      if @wait_for > 0
        @wait_for = @wait_for - 1
        return 0
      else
        return @health_failures
      end
    end

    def close
      @socket.close
    end
  end
  
  class Cluster

    def initialize(name)
      @data_lock = Mutex.new
      @rules_lock = Mutex.new
      @nodes = []
      @latest = Hash.new
      @name = name
      @rules, @metrics = Rule.get_rules_for_cluster(name)
      @data = Array.new
      @data.max_size = Server.max_size
      @averages = Array.new
      @averages.max_size = Server.max_size
      puts "Cluster #{name} is initialized"
    end
    
    def add_node(node)
      #create a thread that listens and responds to the node
      @nodes << node
      metric_lines = get_metrics_for_node(node.group_name)
      puts "There are #{@metrics.size} metrics"
      if metric_lines.size > 0
        node.send "info-$-#{Server.interval}-$-#{metric_lines.join("-$$-")}"
        puts "Sending #{metric_lines.join('\/')}"
      else
        node.send "error-$-There are no rules setup yet for your cluster"
        puts "Error, no metrics found for #{@name}, #{node.group_name}"
      end

      Thread.new do
        while true
          input = node.gets

          if !input
            break
          end

          input.chop!
          input = input.split("|")
          type = input[0]
          input.shift

          if type != "data"
            puts "Invalid data from node: #{type} != data"
          else
            node.health_this_go = 1
            @data_lock.lock
            @latest[node.get_name] = Hash.new
            i = 0
            @metrics.each do |metric|
              @latest[node.get_name][metric] = input[i]
              i = i + 1
            end
            @data_lock.unlock

            puts "#{@name}-#{node.get_name} -- #{input.join('|')}"
          end
        end
        puts "Client on #{node.get_name} disconnected from cluster #{@name}."
        @nodes.delete(node)
        node.close
      end
    end

    def get_metrics_for_node(group)
      metric_lines = []
      @metrics.each do |metric|
        if metric != "node_alive"
          if group != ""
            metric_lines << Server.metrics.params[group][metric]
          else
            metric_lines << Server.metrics.params[metric]
          end
        end
      end
      return metric_lines
    end
    
    def on_server_interval
      @data_lock.lock
      @last = @latest
      @latest = Hash.new
      some_health = false
      @nodes.each {|node| some_health = true if node.health_this_go > 0}
      if some_health && @last.size > 0
        average = average_data(@last)
        if average.size > 0
          @averages.push_safe(average)
        end
      else
        puts "All my clients are gone :("
      end
#      @data.push_safe(@latest) #if @last.size > 0
      @data_lock.unlock

      #check to see if u decrement check in it reaches 0 (returns 1 for true)
      @rules.each do |rule|
        if (rule.decrement_check_in == true || rule.metric == "node_alive")
          @rules_lock.lock
            #check the rule, which will fire it on Actions if it's met
            if rule.metric == "node_alive"
              @nodes.each {|node|
                if node.wait_for == 0 #we only want to set wait for if it's 0
                  node.wait_for = rule.check_health(node.check, node.get_name)
                else
                  node.check
                end
              }
            elsif some_health #don't check rules unless data worked this time, except node_dead which obviously needs to run
              rule.check_rule(@averages)
            end
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
        last.each do |hostname, node|
          total_metric_value += node[metric_name].to_f
        end
        average[metric_name] = total_metric_value / last.size
        string = string + "#{metric_name}: #{average[metric_name]}, "
        size = last.size
        puts "#{@name}: #{string} with #{size} nodes"
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
            @@clusters.each_value {|cluster| cluster.on_server_interval}
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
          node = @listener.accept
          Thread.start(node) do |c|
            input = c.gets

            if !input
              break
            end

            input.chop!
            input = input.split("|")
            type = input[0]
            input.shift

            if type != "info"
              puts "ERROR- the node isn't speaking my language - he said #{type} rather than giving me info"
            else
              input[0] ||= c.peeraddr[2]
              input[0] = c.peeraddr[2] if input[0] == ""
              if @@clusters.include?(input[0]) == false
                puts "Creating cluster #{input[0]}"
                @@clusters[input[0]] = Cluster.new(input[0])
              else
                puts "Clusters already has #{input[0]}"
              end

              @@clusters[input[0]].add_node(Node.new(c, input[1]))
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