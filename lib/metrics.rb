require File.dirname(__FILE__) + '/../lib/parseconfig.rb'
class Metrics
  WorkingDirectory = File.expand_path(File.dirname(__FILE__))  
  
  def initialize
    @conf = ParseConfig.new(WorkingDirectory + '/../etc/metrics.conf')
  end
  
  def get(metric)
    cmd = %x[#{@conf.params[metric]}]
  end
end