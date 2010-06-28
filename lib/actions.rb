class Actions
  def self.logSomething(string)
    STDOUT.puts "Rule #{string} was fired"
  end
end