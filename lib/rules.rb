
class Rule
  
  def self.read_in_rules(file_to_read)
    rules = []
    open(file_to_read).each do |line| 
      line.strip!
      if line.length> 0
        rules << Rule.new(line)
      end
    end
    return rules
  end
  
  def initialize(string)
    string = string.split(" ")
    if (string.size >= 6 && string[string.size - 2] == "wait")
      @rule_name = string[0]
      @metric = string[1]
      @operator = string[2]
      @value = string[3].to_i
      if string[4] == "for"
        @threshold = string[5].to_i
        @action = string[7]
        @and_wait = string[10].to_i 
      else
        @threshold = 1
        @action = string[5]
        @and_wait = string[8].to_i
      end
      @check_in = @threshold
    else
      STDOUT.puts "ERROR: #{string[0]} isn't correct"
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
      eval "#{@action}"
      
      @check_in = @and_wait
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