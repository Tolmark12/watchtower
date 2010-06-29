class Actions
  def self.logSomething(string)
    STDOUT.puts "Rule #{string} was fired"
  end
  
  def self.test_regex
    open("../etc/rules.conf").each do |rule|
      rule.strip!
      puts rule
      regex = /^([a-z_]+) if ([a-z]+) ([>=<]+) ([0-9]+) for ([0-9]+) intervals then (call|run|log) (.*) and wait ([0-9]+) intervals/
      
      if rule =~ regex
        answers = rule.scan regex {|name, metric, operator, value, test_interval, actiontype, action, wait_interval|}
        puts answers[0]
      else
        puts "ERROR"
      end
#cpu_is_high if cpu > 90 for 2 intervals then call Action.logSomething("cpu is high") and wait 5 intervals
    end
  end
end
