class AvoidBalancingHost < ActiveRecord::Base
  belongs_to :provider
  acts_as_audited
  validates_presence_of :name, :provider
  validates_format_of :name, :with => /^(?=.{1,255}$)[0-9A-Za-z](?:(?:[0-9A-Za-z]|\b-){0,61}[0-9A-Za-z])?(?:\.[0-9A-Za-z](?:(?:[0-9A-Za-z]|\b-){0,61}[0-9A-Za-z])?)*\.?$/

  include ModelsWatcher
  watch_fields :name, :provider_id
  watch_on_destroy

  def ip_addresses
    require 'resolv'
    begin
      Timeout::timeout(3) do
        Resolv.getaddresses(name).select do |a| IP.new(a).is_a?(IP::V4) end
      end
    rescue Timeout::Error
      Rails.logger.error "AvoidBalancingHost::ip_addresses failed to resolv #{name}"
      []
    rescue => e
      Rails.logger.error "AvoidBalancingHost::ip_addresses #{e.inspect}"
      []
    end
  end

  def auditable_name
    "#{self.class.human_name}: #{name}"
  end
end
