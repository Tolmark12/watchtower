class Rule
  @@clusters_rules = Hash.new
  class << self 
    def clusters_rules
      @@clusters_rules
    end
    
    def read_in_rules(file_to_read)
      rules = []
      open(file_to_read).each do |line| 
        line.strip!
        if line.length> 0
          unless (/^\#/.match(line))
            rules << Rule.new(line)
          end
        end
      end
      return rules
    end
  end
  
  def initialize(rule)
    @error = STDOUT
    regex = /^([a-z_]+) if ([a-z]+) (.*)is ([>=<]+) ([0-9]+) for ([0-9]+) intervals then (call|run|log) (.*) and wait ([0-9]+) intervals/
    if rule =~ regex
      rule.scan(regex) {|name, metric, clusters, operator, value, threshold, action_type, action, wait_interval|
        @rule_name = name
        @metric = metric
        @operator = operator
        @value = value.to_i
        clusters.slice!("of ")
        clusters.strip!
        @clusters = clusters.split(" or ")
        if @clusters.size == 0
          if !@@clusters_rules.include?("all")
            @@clusters_rules["all"] = Array.new
          end
          if !@@clusters_rules["all"].include? @metric
            @@clusters_rules["all"] << metric
          end
        else
          @clusters.each do |cluster|
            if !@@clusters_rules.include?(cluster)
              @@clusters_rules[cluster] = Array.new
            end
            if !@@clusters_rules[cluster].include? @metric
              @@clusters_rules[cluster] << @metric
            end
          end
        end
        @threshold = threshold.to_i
        @action_type = action_type
        @action = action
        @wait_interval = wait_interval.to_i 
        @check_in = @threshold
        puts "#{@rule_name}, #{@metric}, #{@operator}, #{@value}, #{@threshold}, #{@action_type}, #{@action}, #{@wait_interval}, #{@check_in}"
      }
    else
      @error.puts "ERROR: #{rule} isn't correct"
    end
  end
  
  def decrement_check_in
    @check_in = @check_in - 1
    if @check_in <= 0
      @check_in = @threshold
      true
    else
      false
    end
  end
  
  def check_rule(data, cluster)
    # if clusters.size == 0 then we want all clusters, otherwise, if the cluster isn't in clusters, then break out.
    if @clusters.size > 0 && @clusters.include?(cluster) == false
      return
    end
    log = STDOUT
    pointer = data.size - 1
    count = @threshold
    # as long as the data meets the rule, count how many times it does
    while (pointer >= 0 && data[pointer].include?(cluster) && check_using_operator(data[pointer][cluster][@metric].to_f, @operator, @value))
      count = count - 1
      pointer = pointer - 1
      if count == 0  # if it meets the rule enough, then don't look over more data
        break
      end
    end
    # at this point, either it found enough, or not
    if count == 0
      # if it found enough: fire off method and reset threshold
      # actionObject.send(@method_name, @rule_name)
      begin
        case @action_type
        when "run"
          puts "Run #{@action}"
          %x[#{@action}]
        when "call"
          puts "Call #{@action}"
          eval "#{@action}"
        when "log"
          puts "Log: #{@action}"
          log.puts @action
        end
      rescue
        puts "Error: rule #{@rule_name}'s action is invalid"
      end
      @check_in = @wait_interval
    else
      # if it didn't find enough, then we want to wait as many more as are required (if it found 2 of 5, then we should check in 3 to see if all 5 met the rule)
      @check_in = count
    end
  end
  
  private
  
  def check_using_operator(data, operator, value)
    case operator
    when ">"
      return data > value
    when ">="
      return data >= value
    when "<"
      return data < value
    when "<="
      return data <= value
    when "="
      return data == value
    end
  end
end