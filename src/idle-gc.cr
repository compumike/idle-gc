require "./idle-gc/idle_detection"
require "./idle-gc/timer"

# IdleGC runs garbage collection periodically in order to keep memory usage low. It attempts to do so when the process is otherwise idle.
#
# To start, just call:
#
# ```
# IdleGC.start
# ```
#
# That is all that most use cases will need! Tweaks and tuning information are below.
#
# In the extremely rare case that your code does not yield or do any I/O, you may need to add explicit calls to `Fiber.yield` to allow IdleGC's background Fiber to have a chance to work.
#
# By default, IdleGC polls every 1 second, and if more than 0 bytes have been allocated on the heap, it runs garbage collection. To make IdleGC less aggressive (and use less CPU time, at the cost of higher memory usage), you may raise both of these settings, for example: `IdleGC::Timer.poll_interval = 5.seconds` and `IdleGC::Timer.bytes_since_gc_threshold = 128*1024`.
#
# Idle detection is based on a measurement of how long it takes `Fiber.yield` to return, and can be tuned with `IdleGC::IdleDetection.idle_threshold=`. If interactive performance (latency) is not a concern for your application, it is recommended that you disable idle detection with `IdleGC::IdleDetection.enabled = false`.
#
# Since idle detection may be inaccurate, there is a `IdleGC::Timer.force_gc_period=` which is set to force a collection every 2 minutes by default. You may disable this with `IdleGC::Timer.force_gc_period = nil`.
#
# You may manually force a collection now with `IdleGC.collect`. Or, if you would like to manually run collection only if idle, call `IdleGC.collect_if_idle`.
class IdleGC
  VERSION = "0.1.0"

  @@mu : Mutex = Mutex.new(Mutex::Protection::Reentrant)
  @@last_checked_at : Time::Span? = nil
  @@last_collected_at : Time::Span? = nil
  @@last_collected_duration : Time::Span? = nil

  ### PUBLIC METHODS

  # Start a background Fiber that runs garbage collection periodically.
  #
  # (Also runs garbage collection immediately.)
  def self.start : Nil
    IdleGC::Timer.start
  end

  # Relative to Time.monotonic, when did IdleGC last check whether or not to run garbage collect?
  #
  # Returns nil if we've never checked.
  def self.last_checked_at : Time::Span?
    mu.synchronize do
      return @@last_checked_at
    end
  end

  # Relative to Time.monotonic, when did IdleGC last initiate GC.collect?
  #
  # Returns nil if we've never collected.
  def self.last_collected_at : Time::Span?
    mu.synchronize do
      return @@last_collected_at
    end
  end

  # How long did GC.collect take to run?
  #
  # Returns nil if we've never collected.
  def self.last_collected_duration : Time::Span?
    mu.synchronize do
      return @@last_collected_duration
    end
  end

  # Explicitly force collection now.
  def self.collect : Nil
    mu.synchronize do
      start_time = Time.monotonic
      GC.collect
      end_time = Time.monotonic

      @@last_checked_at = start_time
      @@last_collected_at = start_time
      @@last_collected_duration = end_time - start_time
    end
  end

  # Collect now, but only if process is idle.
  def self.collect_if_idle : Bool
    if IdleGC::IdleDetection.process_is_idle?
      collect
      true
    else
      false
    end
  end

  ### INTERNAL METHODS

  protected def self.mu : Mutex
    @@mu
  end

  protected def self.last_checked_at=(v : Time::Span?)
    @@last_checked_at = v
  end
end
