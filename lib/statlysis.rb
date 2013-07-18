# encoding: UTF-8
#
# Sequel的操作均需通过Symbol
#
# 删除匹配的统计表
# Statlysis.sequel.tables.select {|i| i.to_s.match(//i) }.each {|i| Statlysis.sequel.drop_table i }

# TODO Statlysis.sequel.tables.map {|t| eval "class ::#{t.to_s.camelize} < ActiveRecord::Base; self.establish_connection Statlysis.database_opts; self.table_name = :#{t}; end; #{t.to_s.camelize}" }

require "active_support/all"
require 'active_support/core_ext/module/attribute_accessors.rb'
require 'active_record'
require 'activerecord_idnamecache'
%w[yaml sequel mongoid].map(&method(:require))

# Fake a Rails environment
module Rails; end

require 'statlysis/constants'

module Statlysis
  class << self
    def setup &blk
      raise "Need to setup proc" if not blk

      logger.info "Start to setup Statlysis"
      time_log do
        self.config.instance_exec(&blk)
      end
      logger.info
    end

    def time_log text = nil
      t = Time.now
      logger.info text if text
      yield if block_given?
      logger.info "Time spend #{(Time.now - t).round(2)} seconds."
      logger.info "-" * 42
    end

    # delagate config methods to Configuration
    def config; Configuration.instance end
    require 'active_support/core_ext/module/delegation.rb'
    [:sequel, :set_database, :check_set_database,
     :set_tablename_default_pre, :tablename_default_pre
    ].each do |sym|
      delegate sym, :to => :config
    end

    def setup_stat_table_and_model cron, tablename = nil
      tablename = cron.stat_table_name if tablename.nil?
      tablename ||= cron.stat_table.first_source_table
      cron.stat_table = Statlysis.sequel[tablename.to_sym]

      str = tablename.to_s.singularize.camelize
      eval("class ::#{str} < Sequel::Model;
        self.set_dataset :#{tablename}
        def self.[] item_id
          JSON.parse(find_or_create(:pattern => item_id).result) rescue []
        end
      end; ")
      cron.stat_model = str.constantize
    end

    delegate :logger, :to => $stdout
  end

end

require 'statlysis/configuration'
require 'statlysis/common'
require 'statlysis/timeseries'
require 'statlysis/clock'
require 'statlysis/rake'
require 'statlysis/cron'
require 'statlysis/similar'


# load rake tasks
module Statlysis
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path('../statlysis/rake.rb', __FILE__)
    end
  end
end if defined? Rails::Railtie
