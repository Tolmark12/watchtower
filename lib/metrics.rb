require File.dirname(__FILE__) + '/../lib/parseconfig.rb'
class Metrics
  WorkingDirectory = File.expand_path(File.dirname(__FILE__))  
  
  def initialize
    @conf = ParseConfig.new(WorkingDirectory + '/../etc/metrics.conf')
  end
  
  def get(metric, group = "")
    if (group == "")
      cmd = @conf.params['default'][metric]
    else
      cmd = @conf.params[group][metric]
    end
  end
    
end