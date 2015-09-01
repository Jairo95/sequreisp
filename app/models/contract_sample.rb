class ContractSample < ActiveRecord::Base
  belongs_to :contract

  # PERIOD    AMPLITUD              TIME_SAMPLE           SAMPLES_SIZE   SAMPLES_SIZE_SATURA
  #   0       180.min (3.hours)        1.min                  180        180 + 5 = 185
  #   1      1440.min (1.day)          5.min                  288        288 + 6 = 294
  #   2     10080.min (1.week)        30.min                  336        336 + 6 = 342
  #   3     44640.min (1.month)      180.min (3.hours)        348        348 + 8 = 356
  #   4    525600.min (1.year)      1440.min (24.hours)       365        365

  CONF_PERIODS = { :period_0 => { :period_number => 0, :time_sample => 1,    :sample_size => 180, :sample_size_cut => 185, :excess_count => 5,   :scope => 180.minutes    },
                   :period_1 => { :period_number => 1, :time_sample => 5,    :sample_size => 288, :sample_size_cut => 294, :excess_count => 6,   :scope => 1440.minutes   },
                   :period_2 => { :period_number => 2, :time_sample => 30,   :sample_size => 336, :sample_size_cut => 342, :excess_count => 6,   :scope => 10080.minutes  },
                   :period_3 => { :period_number => 3, :time_sample => 180,  :sample_size => 348, :sample_size_cut => 356, :excess_count => 8,   :scope => 44640.minutes  },
                   :period_4 => { :period_number => 4, :time_sample => 1440, :sample_size => 348, :sample_size_cut => nil, :excess_count => nil, :scope => 525600.minutes } }

  named_scope :for_period, lambda { |period| {:conditions => "contract_samples.period = #{period}"} }


  named_scope :total_samples_for_period, :select => 'COUNT(*) as total_samples, contract_samples.*',
                                         :group  => 'contract_id'

  named_scope :last_samples, lambda{|period| { :conditions => "sample_number IN (SELECT MAX(sample_number)
                                                                                 FROM contract_samples
                                                                                 WHERE period = #{period}
                                                                                 GROUP BY contract_id )
                                                                             AND period = #{period}"}}

  named_scope :samples_to_compact, lambda { |id,limit| { :conditions => "contract_samples.contract_id = #{id}",
                                                         :limit => limit } }

  def self.sample_conf
    conf = CONF_PERIODS
    ContractSample.transaction {
      conf.each_key do |key|
        last = ContractSample.last_samples(conf[key][:period_number]).all
        conf[key][:samples_to_compact] = {}
        conf[key][:last_sample_time] = {}

        ContractSample.for_period(conf[key][:period_number]).total_samples_for_period.all.each do |cs|
          conf[key][:last_sample_time][cs.contract_id]   = last.find{ |ls| ls.contract_id == cs.contract_id }.sample_number.to_i
          conf[key][:samples_to_compact][cs.contract_id] = ContractSample.for_period(conf[key][:period_number]).samples_to_compact(cs.contract_id, conf[key][:excess_count]).all if cs.total_samples.to_i >= conf[key][:sample_size_cut]
        end
      end
    }
    conf
  end


  def self.compact(period, samples)
    new_sample = {}
    compact_keys.each { |rkey| new_sample[rkey[:name].to_sym] = 0 }
    samples.each do |destroy_sample|
      compact_keys.each { |rkey| new_sample[rkey[:name].to_sym] += destroy_sample[rkey[:name]] }
    end

    new_sample
  end

  # this has an alias_method_chain
  def self.compact_keys
    keys = []
    ["up", "down"].each do |prefix|
      ["prio1", "prio2", "prio3"].each { |k| keys << { :sample => k, :up_or_down => prefix, :name => "#{prefix}_#{k}" } }
    end
    keys
  end

  def object
    contract
  end
end
