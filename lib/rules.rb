require 'thread'
module WatchTower
  class Rule
    @@file_lock = Mutex.new

    class << self

      def setup_rules(file_to_read)
        @@file_name = file_to_read
      end

      def get_rules_for_cluster(cluster_name)
        rules = []
        metric_names = []
        health_intervals = []
        @@file_lock.lock
        open(@@file_name).each do |line|
          line.strip!
          if line.length> 0
            unless (/^\#/.match(line))
              #verify that this rule works for this cluster
              regex =
              line.scan(/^([a-z_]+ if [a-z_]+ )(.*?)is(.*)/) {|worthless, clusters, worthless|
                clusters.slice!("of ")
                clusters.strip!
                cluster_array = clusters.split(" or ")
                
                if cluster_array.size == 0 || cluster_array.include?(cluster_name) || cluster_array.include?("all")
                  #if it does, make it into a rule and return it.
                  rule = Rule.new(line, cluster_name) #assign it to a variable so we can also get the metric name
                  rules << rule
                  puts "#{rule.rule_name},#{cluster_name}"
                  # add the metric name if it's not already there
                  if metric_names.include?(rule.metric) == false
                    metric_names << rule.metric
                  end
                end
              }
            end
          end
        end
        @@file_lock.unlock
        return rules, metric_names
      end
    end

    attr_reader :metric, :rule_name

    def initialize(rule, cluster_name)
      @error = STDOUT
      regex = /^([a-z_]+) if ([a-z_]+) .*is ([>=<]+) ([0-9]+) for ([0-9]+) intervals then (call|run|log) (.*) and wait ([0-9]+) intervals/
      if rule =~ regex
        rule.scan(regex) {|name, metric, operator, value, threshold, action_type, action, wait_interval|
          @rule_name = name
          @metric = metric          
          @operator = operator
          @value = value.to_i
          @cluster = cluster_name  #we know which cluster it belongs too :)
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

    def check_rule(data)
      log = STDOUT
      pointer = data.size - 1
      count = @threshold
      # as long as the data meets the rule, count how many times it does
      while (pointer >= 0 && check_using_operator(data[pointer][@metric].to_f, @operator, @value))
        count = count - 1
        pointer = pointer - 1
        if count == 0  # if it meets the rule enough, then don't look over more data
          break
        end
      end
      # at this point, either it found enough, or not (i do it this way so there is 1 point of exit
      if count == 0
        # if it found enough: fire off method and reset threshold
        # actionObject.send(@method_name, @rule_name)
        puts "Firing rule #{@rule_name} for cluster #{@cluster}"
        do_action @action_type, @action
        @check_in = @wait_interval
      else
        # if it didn't find enough, then we want to wait as many more as are required (if it found 2 of 5, then we should check in 3 to see if all 5 met the rule)
        @check_in = count
      end
    end

    def do_action(type, action)
      begin
        case type
        when "run"
          system(action)
        when "call"
          eval "#{action}"
        when "log"
          puts action
        end
      rescue
        puts "Error: rule #{@rule_name}'s action is invalid"
      end
    end

    def check_health(health, node_name)
      if health >= @threshold
          tmp_action = @action.gsub(/node_name/, node_name)
          do_action @action_type, tmp_action
          return @wait_interval
      else
        return 0
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
end