# Sequreisp - Copyright 2010, 2011 Luciano Ruete
#
# This file is part of Sequreisp.
#
# Sequreisp is free software: you can redistribute it and/or modify
# it under the terms of the GNU Afero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Sequreisp is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Afero General Public License for more details.
#
# You should have received a copy of the GNU Afero General Public License
# along with Sequreisp.  If not, see <http://www.gnu.org/licenses/>.

class Provider < ActiveRecord::Base
  DYNAMIC_PROVIDER_PATH="/tmp/sequreisp"

  acts_as_audited
  belongs_to :provider_group
  belongs_to :interface
  has_one :klass, :as => :klassable, :class_name => "ProviderKlass", :dependent => :nullify
  has_many :addresses, :as => :addressable, :class_name => "Address", :dependent => :destroy
  accepts_nested_attributes_for :addresses, :reject_if => lambda { |a| a[:ip].blank? }, :allow_destroy => true
  has_many :forwarded_ports, :dependent => :destroy
  has_many :unique_provider_contracts, :class_name => "Contract", :foreign_key => 'unique_provider_id', :dependent => :nullify
  has_many :avoid_balancing_hosts, :dependent => :nullify
  has_many :proxy_arp_contracts, :class_name => "Contract", :foreign_key => 'proxy_arp_provider_id', :dependent => :nullify
  #named_scope :working, :conditions => "state = 'enabled' and online = 1 and ip not null and netmask not null and gateway not null"
  named_scope :ready, :conditions => "ip is not null and ip != '' and netmask is not null and netmask != '' and gateway is not null and gateway != ''"
  named_scope :online, :conditions => "online = 1"
  named_scope :offline, :conditions => "online = 0"
  named_scope :descend_by_online_changed_at, :order => "online_changed_at DESC"
  named_scope :with_klass_and_interface, :include => [:klass, :interface]

  include ModelsWatcher
  watch_fields :provider_group_id, :interface_id, :kind, :ip, :netmask, :gateway,
               :rate_down, :rate_up, :pppoe_user, :pppoe_pass, :state,
               :unique_mac_address, :arp_ignore, :arp_announce, :arp_filter,
               :shape_rate_down_on_ingress, :dhcp_force_32_netmask, :avoid_nat_addresses,
               :allow_dns_queries
  watch_on_destroy

  validates_presence_of :name, :interface, :provider_group, :rate_down, :rate_up
  validates_presence_of :ip, :netmask, :gateway, :if => Proc.new { |p| p.kind == "static" }
  validates_presence_of :pppoe_user, :pppoe_pass, :if => Proc.new { |p| p.kind == "adsl" }
  validates_length_of :name, :in => 3..128
  validates_format_of :netmask, :with => /^([12]{0,1}[0-9]{0,1}[0-9]{1}\.){3}[12]{0,1}[0-9]{0,1}[0-9]{1}$/, :allow_blank => true
  validates_numericality_of :rate_down, :rate_up, :only_integer => true
  validates_inclusion_of :kind, :in => %w( static adsl dhcp )
  validates_uniqueness_of :interface_id, :name
  validates_uniqueness_of :ip, :allow_nil => true, :allow_blank => true

  def validate
    if not ip.blank?
      # Address tiene las ips de las interfaces y los  proveedores
      if Address.find_by_ip(ip) or Contract.find_by_ip(ip)
        errors.add(:ip, I18n.t('validations.ip_already_in_use'))
      end
    end
  end
  validate :unique_provider_contracts_on_group_change

  def unique_provider_contracts_on_group_change
    if provider_group_id_changed? and unique_provider_contracts.count > 0
      errors.add(:provider_group, I18n.t('validations.provider.provider_group_can_not_be_changed_if_unique_provider_contracts_exists'))
    end
  end
  include IpAddressCheck
  validate_ip_format_of :ip, :gateway

  validate :avoid_nat_addresses_format
  def avoid_nat_addresses_format
    if avoid_nat_addresses.present?
      #avoid_addresses = avoid_nat_addresses.split("\n")
      avoid_nat_addresses.each_line do |ad|
        ad.chomp!
        unless ip = IP.new(ad) rescue nil
          errors.add :avoid_nat_addresses, I18n.t('validations.provider.invalid_avoid_nat_addresses',:invalid_ip => ad)
          break
        end
      end
    end
  end

  def avoid_nat_addresses_as_ips
    ips = []
    if avoid_nat_addresses.present?
      avoid_nat_addresses.each_line.collect do |ad|
        ad.chomp!
        if ip = IP.new(ad) rescue nil
          ips << ip if ip.is_a?(IP::V4)
        end
      end
    end
    ips
  end
  before_create :set_default_online_changed_at
  def set_default_online_changed_at
    self.online_changed_at = Time.now
  end

  def online= val
    write_attribute :online, val
    self.online_changed_at = Time.now if self.online_changed?
  end

  include OverflowCheck
  before_save :check_integer_overflow
  before_create :set_defaults

  after_update :queue_update_commands
  after_destroy :queue_destroy_commands

  def queue_update_commands
    cq = QueuedCommand.new
    if not interface_id_was.nil?
      _interface = Interface.find interface_id_was
      if kind_changed? or interface_id_changed?
        case kind_was
        when "adsl"
          cq.command += "poff #{_interface.name};"
          cq.command += "rm #{SequreispConfig::CONFIG["ppp_dir"]}/peers/#{_interface.name};"
        when "dhcp"
          #kill del dhclient
          cq.command += "kill $(cat /var/run/dhclient.#{_interface.name}.pid);"
        end
        cq.command += "ip address flush dev #{_interface.name};"
      elsif pppoe_user_changed? or pppoe_pass_changed?
        cq.command += "poff -r #{interface.name};"
      end
      if ip_changed? and kind_was == "static"
        cq.command += "ip address flush dev #{_interface.name};"
      end
    end
    cq.save if not cq.command.empty?
  end

  def queue_destroy_commands
    cq = QueuedCommand.new
    case kind
    when "adsl"
      cq.command += "poff #{interface.name};"
      cq.command += "rm #{SequreispConfig::CONFIG["ppp_dir"]}/peers/#{interface.name};"
    when "dhcp"
      #kill del dhclient
      cq.command += "kill $(cat /var/run/dhclient.#{interface.name}.pid);"
    end
    cq.command += "ip address flush dev #{interface.name};"
    cq.save if not cq.command.empty?
  end

  #AASM conf http://github.com/rubyist/aasm
  include AASM
  aasm_column :state
  aasm_initial_state :enabled
  aasm_state :enabled rescue nil
  aasm_state :disabled rescue nil

  aasm_event :enable do
    transitions :from => [:disabled], :to => :enabled
  end
  aasm_event :disable do
    transitions :from => [:enabled], :to => :disabled
  end

  def self.aasm_states_for_select
    AASM::StateMachine[self].states.map { |state| [I18n.t("aasm.provider.#{state.name.to_s}"),state.name.to_s] }
  end

  after_create :bind_klass

  def bind_klass
    self.klass = ProviderKlass.find(:first, :conditions => "klassable_id is null", :lock => "for update")
    raise "TODO nos quedamos sin clases!" if self.klass.nil?
  end

  def set_defaults
    #self.online = true
  end

  def netmask_suffix
    begin
      mask = IP.new(self.netmask).to_i
      count = 0
      while mask > 0 do
        mask-=(2**(31-count))
        count+=1;
      end
      count
    rescue
      nil
    end
  end
  def ruby_ip
    IP.new("#{self.ip}/#{netmask_suffix}") rescue nil
  end
  def network
    ruby_ip.network.to_s rescue nil
  end
  def networks
    begin
      result = []
      result << self.network
      self.addresses.each do |a|
        result << a.network
      end
      result.uniq.compact
    rescue
      []
    end
  end
  def quantum_factor
    (provider_group.plans.collect{|plan| plan.rate_down + plan.ceil_down }.max)/Configuration.quantum_factor.to_i rescue 1
  end
  def status
    self.online ? "online" : "offline"
  end
  def has_ip?
    begin
      IP.new(self.ip) and IP.new(self.gateway) and !self.netmask.blank?
    rescue
      false
    end
  end
  def link_interface
    if self.kind == "adsl"
      pppoe_interface
    else
      self.interface.name
    end
  end
  def pppoe_interface
    "ppp" + self.klass.number.to_s
  end
  def default_route
    "default via #{self.gateway} dev #{self.link_interface}  proto static onlink"
  end
  def self.fallback_default_route(alt_format=false)
    providers = Provider.enabled.ready.online
    case providers.count
    when 0
      ""
    when 1
      p = providers.first
      if alt_format
        "default via #{p.gateway} dev #{p.link_interface}  proto static onlink"
      else
        "default via #{p.gateway} dev #{p.link_interface} onlink proto static"
      end
    else
      route = ""
      providers.each do |p|
        route += "  nexthop via #{p.gateway}  dev #{p.link_interface} weight #{p.weight} onlink"
      end
      "default  proto static #{route}"
    end
  end
  def weight
    # max 256 (from iproute.c)
    # dinamic quantum from the bigest rate_down provider
    _quantum = Provider.enabled.first(:order => 'rate_down DESC').rate_down/255.0
    _weight = (self.rate_down/_quantum).round
    _weight > 0 ? _weight : 1
  end
  def check_link_table
    self.klass.number << 8
  end
  def table
    self.klass.number
  end
  def class_hex
    self.klass.number.to_s(16)
  end
  def mark_hex
    mark.to_s(16)
  end
  def mark
    self.klass.number << 16
  end
  def mac_address
    # unique mac_address basado en el nro de classe
    # primer BYTE terminado en 10 (locally generated && not broadcast)
    _interface = interface.vlan? ? interface.vlan_interface : interface
    real_mac = `ip li show dev #{_interface.name} 2>/dev/null`.match(/link\/ether ([0-9a-fA-F:]+)/)[1].split(":")[0..4].join(":") rescue nil
    # verify that real_mac is valid
    if real_mac.present? and real_mac.match(/^([0-9A-Fa-f]{2}\:){4}[0-9A-Fa-f]{2}$/)
      "#{real_mac}:#{class_hex}"
    else
      # la morenita...
      "ca:fe:ca:fe:00:#{class_hex}"
    end
  end

  def self.kinds_for_select
    [[I18n.t("selects.provider.kind.static"), "static"], [I18n.t("selects.provider.kind.adsl"), "adsl"],[I18n.t("selects.provider.kind.dhcp"),"dhcp"]]
  end

  def to_ppp_peer
    string = ""
    string += "noipdefault" + "\n"
    string += "nodefaultroute" + "\n"
    string += "hide-password" + "\n"
    string += "lcp-echo-interval 20" + "\n"
    string += "lcp-echo-failure 3" + "\n"
    string += "connect /bin/true" + "\n"
    string += "noauth" + "\n"
    string += "persist" + "\n"
    string += "maxfail 0" + "\n"
    string += "mtu 1492" + "\n"
    string += "noaccomp" + "\n"
    string += "default-asyncmap" + "\n"
    string += "pty \"/usr/sbin/pppoe -I #{self.interface.name} -U -T 80 -m 1412\"" + "\n"
    string += "user \"#{self.pppoe_user}\"" + "\n"
    string += "password \"#{self.pppoe_pass}\"" + "\n"
    string += "ipparam #{self.interface.name}" + "\n"
    string += "unit #{self.klass.number}" + "\n"
    string
  end

  def current_status_time
    Time.now - self.online_changed_at
  end

  def pretty_current_status_time
    cst = current_status_time.to_i

    seconds = cst % 60
    minutes = (cst / 60)%60
    hours = (cst / 3600)%24
    days = cst / 86400

    if minutes.zero? and hours.zero? and days.zero?
      "#{seconds} #{I18n.t('datetime.current_status_time.seconds')}"
    elsif hours.zero? and days.zero?
      "#{minutes} #{I18n.t('datetime.current_status_time.minutes')}"
    elsif days.zero?
      sprintf("%.2d", hours) + ":" + sprintf("%.2d", minutes) + " " + I18n.t('datetime.current_status_time.hours')
    else
      "#{days} #{I18n.t('datetime.current_status_time.days')}, " +  sprintf("%.2d", hours) + ":" + sprintf("%.2d", minutes) + " " + I18n.t('datetime.current_status_time.hours')
    end
  end

  def offline_time
    self.online ? 0 : current_status_time
  end

  def nat_pool_addresses
    [ip] + addresses.all(:conditions => "use_in_nat_pool = 1").collect(&:ip)
  end

  def auditable_name
    "#{self.class.human_name}: #{name}"
  end

  def is_online_by_rate?
    Rails.logger.debug "Provider::is_online_by_rate? #{Time.now} provider_id: #{id} start"
    rx = interface.rx_bytes
    tx = interface.tx_bytes
    sleep 2
    # from bytes to bits(*8) to bps(/2) to kbps(/1024)
    instant_rate_down = (interface.rx_bytes-rx)*8/2/1024
    instant_rate_up = (interface.tx_bytes-tx)*8/2/1024
    # min rates in kbps
    min_online_rate_down = 256
    min_online_rate_up = 56
    result = (instant_rate_down > min_online_rate_down and instant_rate_up > min_online_rate_up)
    Rails.logger.debug "Provider::is_online_by_rate? #{Time.now} provider_id: #{id} result:#{result} down: #{instant_rate_down} up #{instant_rate_up}"
    result
  end

  def max_quantum
    Configuration.first.mtu * quantum_factor * 3
  end

  def tc_class_qdisc_filter(o = {})
    classid = "#{o[:parent_mayor]}:#{o[:current_minor]}"
    tc_rules = []
    tc_rules << "class add dev #{self.link_interface} parent #{o[:parent_mayor]}:#{o[:parent_minor]} classid #{classid} htb rate #{o[:rate]}kbit ceil #{o[:ceil]}kbit prio #{o[:prio]} quantum #{o[:quantum]}"
    tc_rules << "qdisc add dev #{self.link_interface} parent #{classid} sfq perturb 10" #saco el handle
    tc_rules << "filter add dev #{self.link_interface} parent #{o[:parent_mayor]}: protocol all prio 200 handle 0x#{o[:mark]}/0x#{o[:mask]} fw classid #{classid}"
    tc_rules
  end

  def do_global_prios_tc(parent_mayor, parent_minor, iface, direction)
    tc_rules = []
    mask = "f0000000"
    quantum = p.max_quantum

    #TODO tc_global ceil_prio3 quantum mark, etc
    #prio1
    tc_rules << tc_class_qdisc_filter(:parent_mayor => parent_mayor,
                                      :parent_minor => parent_minor,
                                      :current_minor => "a",
                                      :rate => self["rate_" + direction] * 0.4 ,
                                      :ceil => self["rate_" + direction],
                                      :prio => 1,
                                      :quantum => quantum,
                                      :mark => "a0000000",
                                      :mask => mask)
    #prio2
    tc_rules << tc_class_qdisc_filter(:parent_mayor => parent_mayor,
                                      :parent_minor => parent_minor,
                                      :current_minor => "b",
                                      :rate => self["rate_" + direction] * 0.5 ,
                                      :ceil => self["rate_" + direction],
                                      :prio => 2,
                                      :quantum => quantum,
                                      :mark => "b0000000",
                                      :mask => mask)
    #prio3
    tc_rules << tc_class_qdisc_filter(:parent_mayor => parent_mayor,
                                      :parent_minor => parent_minor,
                                      :current_minor => "c",
                                      :rate => self["rate_" + direction] * 0.1,
                                      :ceil => self["rate_" + direction] * 0.3 ,
                                      :prio => 3,
                                      :quantum => quantum / 3,
                                      :mark => "c0000000",
                                      :mask => mask)
    tc_rules.flatten
  end

  def self.all_ips
    provider_ips = []
    Provider.online.ready.each do |provider|
      provider_ips << provider.ip
      provider.addresses.each { |addr| provider_ips << addr.ip }
    end
    provider_ips.compact
  end

  def ip_in_cidr
    cidr = IPAddr.new("#{ip}/#{netmask}").cidr_mask
    "#{ip}/#{cidr}"
  end

end
