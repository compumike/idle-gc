class PeriodicGC
  VERSION = "0.1.0"

  DEFAULT_POLL_INTERVAL = 1.second

  @@mu : Mutex = Mutex.new
  @@running : Channel(Nil)? = nil
  @@poll_interval : Time::Span = DEFAULT_POLL_INTERVAL

  def self.poll_interval=(v : Time::Span)
    @@mu.synchronize do
      @@poll_interval = v
    end
  end

  def self.start : Nil
    @@mu.synchronize do
      return if @@running

      @@running = spawn_loop
    end
  end

  def self.stop : Nil
    @@mu.synchronize do
      stop_channel = @@running
      if !stop_channel.nil?
        stop_channel.close
        @@running = nil
      end
    end
  end
  
  protected def self.spawn_loop : Channel(Nil)
    stop_channel = Channel(Nil).new

    spawn do
      loop do
        break if stop_channel.closed?

        loop_callback
      end
    end

    stop_channel
  end

  protected def self.loop_callback : Nil
    sleep_period : Time::Span? = nil

    @@mu.synchronize do
      collect_if_needed!
      sleep_period = @@poll_interval
    end

    sleep(sleep_period.not_nil!)
  end

  protected def self.collect_if_needed!
    GC.collect if GC.stats.bytes_since_gc > 0
  end
end
