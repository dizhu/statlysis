# encoding: UTF-8
#
# see original implementation at http://mvj3.github.io/2013/04/17/statlysis-analysis-design-solve-two-problems-lazy-loading-and-scope/
#

require 'singleton'

module Statlysis
  class Configuration
    include Singleton

    attr_accessor :sequel, :default_time_columns, :default_time_zone, :database_opts, :tablename_default_pre
    attr_accessor :is_skip_database_index
    TimeUnits.each {|unit| module_eval "attr_accessor :#{unit}_crons; self.instance.#{unit}_crons = []" }
    [:realtime, :similar, :hotest].each do |sym|
      sym = "#{sym}_crons"
      attr_accessor sym; self.instance.send "#{sym}=", []
    end
    self.instance.send "tablename_default_pre=", "st"
    self.instance.send "is_skip_database_index=", false

    # 会在自动拼接统计数据库表名时去除这些时间字段
    def update_time_columns *columns
      self.default_time_columns ||= [:created_at, :updated_at]
      columns.each {|column| self.default_time_columns.push column }
      self.default_time_columns = self.default_time_columns.uniq
    end

    def set_database sym_or_hash
      self.database_opts = if sym_or_hash.is_a? Symbol
        YAML.load_file(Rails.root.join("config/database.yml"))[sym_or_hash.to_s]
      elsif Hash
        sym_or_hash
      else
        raise "Statlysis#set_database only support symbol or hash params"
      end
      self.sequel = Sequel.connect(self.database_opts)

      # 初始化键值model
      ["#{self.tablename_default_pre}_single_kvs", "#{self.tablename_default_pre}_single_kv_histories"].each do |tn|
        Utils.setup_pattern_table_and_model tn
      end
      return self
    end

    def set_default_time_zone zone
      self.default_time_zone = zone
      return self
    end

    def set_tablename_default_pre str
      self.tablename_default_pre = str.to_s
    end

    def daily  source, opts = {}; timely source, {:time_unit => :day }.merge(opts) end
    def hourly source, opts = {}; timely source, {:time_unit => :hour}.merge(opts) end

    def check_set_database; raise "Please setup database first" if sequel.nil?  end

    def timely source, opts
      self.check_set_database
      opts.reverse_merge! :time_column => :created_at, :time_unit => :day
      t = Timely.new source, opts
      self.send("#{opts[:time_unit]}_crons").push t
    end

    # the real requirement is to compute lastest items group by special pattens, like user_id, url prefix, ...
    def lastest_visits source, opts
      self.check_set_database
      opts.reverse_merge! :time_column => :created_at
      self.realtime_crons.push LastestVisits.new(source, opts)
    end

    # TODO 为什么一层proc的话会直接执行的
    def hotest_items key, id_to_score_and_time_hash = {}
      _p = proc { if block_given?
        (proc do
          id_to_score_and_time_hash = Hash.new
          yield id_to_score_and_time_hash
          id_to_score_and_time_hash
        end)
      else
        (proc { id_to_score_and_time_hash })
      end}

      self.hotest_crons.push HotestItems.new(key, _p)
    end

    # TODO support mongoid
    def similar_items model_name, id_to_text_hash = {}
      _p = if block_given?
        (proc do
          id_to_text_hash = Hash.new {|hash, key| hash[key] = "" }
          yield id_to_text_hash
          id_to_text_hash
        end)
      else
        (proc { id_to_text_hash })
      end

      self.similar_crons.push Similar.new(model_name, _p)
    end

  end
end
