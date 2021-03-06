require 'rubygems'
require "eventmachine"
require 'em-hiredis'
require 'redis'
require "active_support/core_ext"
require 'yajl'
require 'sinatra/base'
require 'haml'
require 'thin'

module FnordMetric

  @@namespaces = {}

  def self.namespace(key=nil, &block)
    @@namespaces[key] = block
  end

  def self.server_configuration=(configuration)
    @@server_configuration = configuration
  end
  
  def self.default_options(opts)

    opts[:redis_url] ||= "redis://localhost:6379"
    opts[:redis_prefix] ||= "fnordmetric"

    opts[:inbound_stream] = ["0.0.0.0", "1337"] if opts[:inbound_stream].nil?
    opts[:web_interface] = ["0.0.0.0", "4242"] if opts[:web_interface].nil?

    opts[:start_worker] = true if opts[:start_worker].nil?
    opts[:print_stats] = 3 if opts[:print_stats].nil?

    # events that aren't processed after 2 min get dropped
    opts[:event_queue_ttl] ||= 120

    # event data is kept for one month
    opts[:event_data_ttl] ||= 3600*24*30

    # session data is kept for one month
    opts[:session_data_ttl] ||= 3600*24*30

    opts
  end

  def self.start_em(opts)
    EM.run do

      trap("TERM", &method(:shutdown))
      trap("INT",  &method(:shutdown))

      app = embedded(opts)

      if opts[:web_interface]
        begin
          Thin::Server.start(*opts[:web_interface], app)
          log "listening on http##{opts[:web_interface].join(":")}"
        rescue Exception => e
          log "cant start FnordMetric::App. port in use?"
        end
      end

    end
  end

  def self.log(msg)
    puts "[#{Time.now.strftime("%y-%m-%d %H:%M:%S")}] #{msg}"
  end

  def self.error!(msg)
    raise msg if ENV['FNORDMETRIC_ENV'] == 'test'
    puts(msg); exit!
  end

  def self.run
    opts = (defined?(@@server_configuration) && @@server_configuration) || {}
    start_em(opts) 
  rescue Exception => e
    log "!!! eventmachine died, restarting... #{e.message}"
    sleep(1); run 
  end

  def self.shutdown
    log "shutting down, byebye"
    EM.stop
  end

  def self.connect_redis(redis_url)
    EM::Hiredis.connect(redis_url)
  end

  def self.print_stats(opts, redis) # FIXME: refactor this mess
    keys = [:events_received, :events_processed]
    redis.llen("#{opts[:redis_prefix]}-queue") do |queue_length|
      redis.hmget("#{opts[:redis_prefix]}-stats", *keys) do |data|
        data_human = keys.size.times.map{|n|"#{keys[n]}: #{data[n]}"}
        log "#{data_human.join(", ")}, queue_length: #{queue_length}"
      end
    end
  end

  def self.standalone
    require "fnordmetric/logger"
    require "fnordmetric/standalone"
  end

  # returns a Rack app which can be mounted under any path.
  # `:start_worker`   starts a worker
  # `:inbound_stream` starts the TCP interface
  # `:print_stats`    periodicaly prints worker stats
  def self.embedded(opts={})
    opts = default_options(opts)
    app  = nil

    if opts[:rack_app] or opts[:web_interface]
      app = FnordMetric::App.new(@@namespaces.clone, opts)
    end

    EM.next_tick do
      if opts[:start_worker]
        worker = Worker.new(@@namespaces.clone, opts)
        worker.ready!
      end

      if opts[:inbound_stream]
        begin
          inbound_stream = InboundStream.start(opts)
          log "listening on tcp##{opts[:inbound_stream].join(":")}"
        rescue
          log "cant start FnordMetric::InboundStream. port in use?"
        end
      end

      if opts[:print_stats]
        redis = connect_redis(opts[:redis_url])
        EM::PeriodicTimer.new(opts[:print_stats]) do
          print_stats(opts, redis)
        end
      end
    end

    app
  end

end

require "fnordmetric/api"
require "fnordmetric/inbound_stream"
require "fnordmetric/worker"
require "fnordmetric/widget"
require "fnordmetric/timeline_widget"
require "fnordmetric/numbers_widget"
require "fnordmetric/bars_widget"
require "fnordmetric/toplist_widget"
require "fnordmetric/pie_widget"
require "fnordmetric/namespace"
require "fnordmetric/gauge_modifiers"
require "fnordmetric/gauge_calculations"
require "fnordmetric/context"
require "fnordmetric/gauge"
require "fnordmetric/session"
require "fnordmetric/app"
require "fnordmetric/dashboard"
require "fnordmetric/event"


#require "fnordmetric/metric_api"


#require "fnordmetric/cache"
#require "fnordmetric/report"
#require "fnordmetric/metric"
#require "fnordmetric/average_metric"
#require "fnordmetric/count_metric"
#require "fnordmetric/combine_metric"
#require "fnordmetric/sum_metric"
#require "fnordmetric/widget"

#
#require "fnordmetric/funnel_widget"

