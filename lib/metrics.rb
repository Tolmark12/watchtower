class Metrics
  def getCpuUsage
    cmd = %x[ps aux|awk 'NR > 0 { s +=$3 }; END {print s}']
    cmd.to_i
  end
  
  def getMemUsage
    cmd = %x[free -t -m | egrep "buffers/cache" | awk '{print $3/($3+$4)}']
    cmd.to_f
  end
  
  def getLoadAverage
    cmd = %x[uptime | sed s/^.*averages\\:\\ //g]
    cmd.strip
    # cmd.each do |cmdline|
    #   %x[print '#{cmdline}']
    # end
  end
end