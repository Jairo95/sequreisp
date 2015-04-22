namespace :db do
  desc "Erase and fill database"
  namespace :populate do
    desc "Populate application"
    task :all => :environment do
      require 'faker'

      [Interface,Address,ProviderGroup,Provider,Plan,Client,Contract].each(&:delete_all)

      Interface.create! :name => 'eth0', :vlan => false, :kind => 'wan'
      i = Interface.create! :name => 'eth1', :vlan => false, :kind => 'lan'
      i.addresses.create!(:ip => "192.168.1.1", :netmask => "255.255.255.0")
      i.addresses.create!(:ip => "10.0.0.1", :netmask => "255.255.255.0")
      i.addresses.create!(:ip => "10.0.1.1", :netmask => "255.255.255.0")
      Interface.create! :name => 'eth2', :vlan => false, :kind => 'wan'
      Interface.create! :vlan => true, :vlan_interface => Interface.find_by_name('eth0'), :vlan_id => 3, :kind => 'wan'
      Interface.create! :vlan => true, :vlan_interface => Interface.find_by_name('eth0'), :vlan_id => 2, :kind => 'wan'
      Interface.create! :vlan => true, :vlan_interface => Interface.find_by_name('eth0'), :vlan_id => 11, :kind => 'wan'
      Interface.create! :vlan => true, :vlan_interface => Interface.find_by_name('eth0'), :vlan_id => 12, :kind => 'wan'
      Interface.create! :vlan => true, :vlan_interface => Interface.find_by_name('eth0'), :vlan_id => 13, :kind => 'wan'
      Interface.create! :vlan => true, :vlan_interface => Interface.find_by_name('eth0'), :vlan_id => 14, :kind => 'wan'
      Interface.create! :vlan => true, :vlan_interface => Interface.find_by_name('eth0'), :vlan_id => 15, :kind => 'wan'

      ProviderGroup.create!( :name => "ComSat")
      ProviderGroup.create!( :name => "IFX")
      ProviderGroup.create!( :name => "ADSLs")
      provider_comsat = Provider.create!(
        :provider_group => ProviderGroup.find_by_name("ComSat"),
        :interface => Interface.find_by_name("eth0.3"),
        :kind => "static",
        :name => "ComSat 10Mb Simetrico",
        :ip => "200.100.100.10",
        :netmask => "255.255.255.0",
        :gateway => "200.100.100.1",
        :online => true,
        :rate_down => "10240",
        :rate_up => "10240"
      )
      provider_comsat.addresses.create!(:ip => "200.100.100.11", :netmask => "255.255.255.0")
      provider_comsat.addresses.create!(:ip => "200.100.101.2", :netmask => "255.255.255.0")
      provider_comsat.addresses.create!(:ip => "200.100.101.3", :netmask => "255.255.255.0")
      p = Provider.create!(
        :provider_group => ProviderGroup.find_by_name("IFX"),
        :interface => Interface.find_by_name("eth0.2"),
        :kind =>"static",
        :name => "IFX 5Mb Simetrico",
        :ip => "200.0.0.2",
        :netmask => "255.255.255.0",
        :gateway => "200.0.0.1",
        :online => true,
        :rate_down => "5120",
        :rate_up => "5120"
      )
      p.addresses.create!(:ip => "200.0.0.3", :netmask => "255.255.255.0")
      p.addresses.create!(:ip => "200.0.0.4", :netmask => "255.255.255.0")
      Provider.create!(
        :provider_group => ProviderGroup.find_by_name("ADSLs"),
        :interface => Interface.find_by_name("eth0.11"),
        :kind =>"adsl",
        :name => "Speedy 1",
        :online => true,
        :rate_down => "5120",
        :rate_up => "1024",
        :pppoe_user => "test@speedy.com.ar",
        :pppoe_pass => "123456"
      )
      Provider.create!(
        :provider_group => ProviderGroup.find_by_name("ADSLs"),
        :interface => Interface.find_by_name("eth0.12"),
        :kind =>"adsl",
        :name => "Speedy 2",
        :online => true,
        :rate_down => "5120",
        :rate_up => "1024",
        :pppoe_user => "test@speedy.com.ar",
        :pppoe_pass => "123456"
      )
      Provider.create!(
        :provider_group => ProviderGroup.find_by_name("ADSLs"),
        :interface => Interface.find_by_name("eth0.13"),
        :kind =>"adsl",
        :name => "Speedy 3",
        :online => true,
        :rate_down => "2048",
        :rate_up => "512",
        :pppoe_user => "test@speedy.com.ar",
        :pppoe_pass => "123456"
      )
      Provider.create!(
        :provider_group => ProviderGroup.find_by_name("ADSLs"),
        :interface => Interface.find_by_name("eth0.14"),
        :kind =>"adsl",
        :name => "Speedy 4",
        :online => false,
        :rate_down => "2048",
        :rate_up => "512",
        :pppoe_user => "test@speedy.com.ar",
        :pppoe_pass => "123456"
      )
      plan_comsat_simetrico_2m = Plan.create!(
        :name => "Compartido Simetrico hasta 2M",
        :provider_group => ProviderGroup.find_by_name("ComSat"),
        :ceil_down => 2048,
        :ceil_up => 2048
      )
      Plan.create!(
        :name => "Dedicado Simetrico 128kbps",
        :provider_group => ProviderGroup.find_by_name("ComSat"),
        :ceil_down => 128,
        :ceil_up => 128
      )
      Plan.create!(
        :name => "Compartido Simetrico hasta 1M",
        :provider_group => ProviderGroup.find_by_name("IFX"),
        :ceil_down => 1024,
        :ceil_up => 1024
      )
      Plan.create!(
        :name => "Compartido Asimetrico hasta 1024/256kbps",
        :provider_group => ProviderGroup.find_by_name("ADSLs"),
        :ceil_down => 1024,
        :ceil_up => 256
      )
      Plan.create!(
        :name => "Compartido Asimetrico hasta 512/128kbps",
        :provider_group => ProviderGroup.find_by_name("ADSLs"),
        :ceil_down => 512,
        :ceil_up => 128
      )

      plans = Plan.all.collect(&:id)
      ip4=2
      ip3=1
      30.times do
        client = Client.create!(:name => Faker::Name.name, :email => Faker::Internet.email, :phone => Faker::PhoneNumber.phone_number)
        Contract.create!(
          :created_at => DateTime.now<<2,
          :ip => "192.168.#{ip3}.#{ip4.to_s}",
          :ceil_dfl_percent => 70,
          :client_id => client.id,
          :plan_id => plans.sort_by{rand}.first,
          :detail => Faker::Lorem.words(1),
          :cpe => Faker::Lorem.words(1),
          :node => Faker::Lorem.words(1)
        )
        ip4+=1
        if ip4==254
          ip3+=1
          ip4=2
        end
      end
      c = Contract.first
      c.plan = plan_comsat_simetrico_2m
      c.public_address = provider_comsat.addresses.first
      c.save
      c = Contract.first(:offset => 1)
      c.forwarded_ports << ForwardedPort.create(:provider => c.plan.provider_group.providers.first, :public_port => 8080, :private_port => 80, :tcp => true)
      c.forwarded_ports << ForwardedPort.create(:provider => c.plan.provider_group.providers.first, :public_port => 8081, :private_port => 81, :tcp => true)
      c.forwarded_ports << ForwardedPort.create(:provider => c.plan.provider_group.providers.first, :public_port => 8082, :private_port => 82, :tcp => true)
    end
  end
end
