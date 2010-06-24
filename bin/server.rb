require File.dirname(__FILE__) + '/../lib/daemon.rb'
require File.dirname(__FILE__) + '/../lib/parseconfig.rb'
require File.dirname(__FILE__) + '/../lib/max_queue.rb' #overwrite array to have max_size and push_safe
require 'socket'

class WatchTowerServer < Daemon::Base
  WorkingDirectory = File.expand_path(File.dirname(__FILE__))  
  @data = Hash.new
  #static methods
  class << self
    def start
      conf = ParseConfig.new(WorkingDirectory + '/../etc/server.conf')
      port = conf.params['server_port']
      max_size = conf.params['max_size'].to_i
      if (max_size == 0)
        max_size = 100
      end
        
      @listener = TCPServer.open(port)
      @sockets = [@listener]
      log = STDOUT
      while true
        # listen for connections
        ready = select(@sockets)
        readable = ready[0]
        
        readable.each do |socket|
          # on connection - create thread
          if socket == @listener
            client = @listener.accept
            @sockets << client
            @data[client.peeraddr[2]] = Array.new
            @data[client.peeraddr[2]].max_size = max_size
            client.puts "Welcome"
            log.puts "Accepted connection from #{client.peeraddr[2]}"
          else
            #   per thread - listen for data
            input = socket.gets
            
            if !input
              log.puts "Client on #{socket.peeraddr[2]} disconnected."
              @data.delete(socket.peeraddr[2])
              @sockets.delete(socket)
              socket.close
              next
            end
            
            input.chop!
            #     on data - split on |
            input = input.split("|")
            type = input[0]
            input.shift
            case type
            when "data"
              @data[socket.peeraddr[2]].push_safe(input)
              log.puts "I got #{input.join('|')} from #{socket.peeraddr[2]} and have #{@data[socket.peeraddr[2]].size} data elements for this one"
            when "info"
              log.puts "I got info from #{socket.peeraddr[2]}"
            end  
            
            #     if data is first, then output "to database - blah"
            #     if info is first, then output "info from the client - blah"
            #     if stop is first, then output "goodbye dear PID", kill thread and close socket.
            
          end
        end
      end
    end
    
    def stop
      #tell all the connections to die
#      @sockets.each do |socket|
#        socket.puts("shutdown")
#        socket.close
#      end
      @listener.close
    end
  end

  #instance methods go here
end

WatchTowerServer.daemonize