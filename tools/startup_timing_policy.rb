# Shared startup acceptance thresholds. Load class describes the document reuse
# state and is independent of whether the app process is cold or warm.
module StartupTimingPolicy
  REVISION = 'startup-r24'
  GOAL_MS = 2000
  HARD_LIMIT_MS = { 'radoc' => 5000, 'first-load' => 10000 }.freeze

  def self.hard_limit_ms(load_class)
    HARD_LIMIT_MS.fetch(load_class) do
      raise ArgumentError, 'load class must be radoc or first-load'
    end
  end
end
