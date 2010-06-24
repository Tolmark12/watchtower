require File.dirname(__FILE__) + '/../lib/daemon.rb'
require File.dirname(__FILE__) + '/../lib/parseconfig.rb'
require 'socket'

class WatchTowerServer < Daemon::Base
  WorkingDirectory = File.expand_path(File.dirname(__FILE__))  
  #static methods
  class << self
    def start
      conf = ParseConfig.new(WorkingDirectory + '/../etc/server.conf')
      port = conf.params['server_port']
      
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
            client.puts "Welcome"
            log.puts "Accepted connection from #{client.peeraddr[2]}"
          else
            #   per thread - listen for data
            input = socket.gets
            
            if !input
              log.puts "Client on #{socket.peeraddr[2]} disconnected."
              @sockets.delete(socket)
              socket.close
              next
            end
            
            input.chop!
            #     on data - split on |
            if (input == 'stop')
              socket.puts("bye")
              log.puts "Closing connection to #{socket.peeraddr[2]}"
              @sockets.delete(socket)
              socket.close
            else
              log.puts "I got #{input} from #{socket.peeraddr[2]}"
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
      @sockets.each do |socket|
        socket.puts("shutdown")
        socket.close
      end
      @listener.close
    end
  end

  #instance methods go here
end

WatchTowerServer.daemonize