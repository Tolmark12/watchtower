
class Rules
  def initialize(metric, operator, value, threshold, method_name, check_in)
    @metric = metric
    @operator = operator
    @value = value
    @threshold = threshold
    @method_name = method_name
    @check_in = check_in
  end
  
  def decrement_check_in
    @check_in--
    if @check_in <= 0
      @check_in = @threshold
      check_rule
    end
  end
  
  def check_rule
    #how do we access the data?
  end
end