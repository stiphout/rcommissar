# Sample Ruby code for the O'Reilly book "Using AWS Infrastructure
# Services" by James Murty.
#
# This code was written for Ruby version 1.8.6 or greater.

require 'thread'

# ThreadPool is a thread pool management class that ensures no more than a
# pre-set number of threads can be run in the background at once.
#
# This code comes from "Ruby Cookbook" by Lucas Carlson and Leonard
# Richardson, published by O'Reilly Media, Inc. ISBN 0-596-52369-6
class ThreadPool
  def initialize(max_size)
    @pool = []
    @max_size = max_size
    @pool_mutex = Mutex.new
    @pool_cv = ConditionVariable.new
  end
#---
  def dispatch(*args)
    Thread.new do
      # Wait for space in the pool.
      @pool_mutex.synchronize do
        while @pool.size >= @max_size
          print "Pool is full; waiting to run #{args.join(',')}...\n" if $DEBUG
          # Sleep until some other thread calls @pool_cv.signal.
          @pool_cv.wait(@pool_mutex)
        end
      end
#---
      @pool << Thread.current
      begin
        yield(*args)
      rescue => e
        exception(self, e, *args)
      ensure
        @pool_mutex.synchronize do
          # Remove the thread from the pool.
          @pool.delete(Thread.current)
          # Signal the next waiting thread that there's a space in the pool.
          @pool_cv.signal
        end
      end
    end
  end

  def shutdown
    @pool_mutex.synchronize { @pool_cv.wait(@pool_mutex) until @pool.empty? }
  end

  def exception(thread, exception, *original_args)
    # Subclass this method to handle an exception within a thread.
    puts "Exception in thread #{thread}: #{exception}"
  end
end
