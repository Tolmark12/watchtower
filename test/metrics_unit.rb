require 'test/unit'
require File.dirname(__FILE__) + '/../lib/metrics.rb'

class MetricsUnitTest < Test::Unit::TestCase
  
  def test_cpu
    s = Metrics.new
    usage = s.get('cpu').to_f
    assert(usage > 0)
    assert(usage <= 100)
  end
  
  def test_memory_usage
    s = Metrics.new
    usedMem = s.get('mem').to_f
    assert(usedMem > 0)
  end
  
  def test_average_load
    s = Metrics.new
    assert_equal(3, s.get('load').split(" ").count)
  end
end