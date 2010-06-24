class Array
  attr_accessor :max_size #The array is accessable in case you need to do things other than push :)
  @max_size = 0
  
  def push_safe(object)
    self.push object
    if (@max_size > 0)
      while (self.length > max_size)
        self.shift
      end
    end
  end
end
