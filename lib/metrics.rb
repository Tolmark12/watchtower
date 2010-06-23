class Metrics
  def get_cpu_usage
    cmd = %x[ps aux|awk 'NR > 0 { s +=$3 }; END {print s}']
    cmd.to_i
  end
  
  def get_mem_usage
    begin
      cmd = %x[free -t -m | egrep "buffers/cache" | awk '{print $3/($3+$4)}']
      cmd.to_f
    rescue
      "Error"
    end
  end
  
  def get_load_average
    cmd = %x[uptime | sed s/^.*averages\\:\\ //g]
    cmd.strip
  end
end