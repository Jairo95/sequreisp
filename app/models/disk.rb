class Disk < ActiveRecord::Base

  include ModelsWatcher
  watch_fields :cache, :free
  watch_on_destroy

  named_scope :system, :conditions => {:system => true}
  named_scope :cache, :conditions => {:cache => true}
  named_scope :free, :conditions => {:free => true}
  named_scope :in_raid, :conditions => ["disks.raid IS NOT NULL AND disks.system = FALSE AND disks.cache = TRUE"]
  named_scope :raid_is, lambda {|raid| { :conditions => ["disks.raid = ?", raid]} }
  named_scope :cache_in_raid, :conditions => ["disks.raid != 'md0' and disks.raid != 'NULL'"]
  named_scope :prepared_for_cache, :conditions => 'prepare_disk_for_cache = 1'
  before_update :clean_cache, :if => "self.free_changed? and self.free"

  def is_mounted?
    system("mount | grep '#{name}' &>/dev/null")
  end
  def self.scan
    disks = {}
    aux =`sudo /usr/bin/lshw -C disk`.strip.split("*-")
    system_disks = used_for_system
    cache_disks = used_for_cache

    aux.each do |disk|
      if disk.include?("disk")
        name = ""
        capacity = ""
        serial = ""
        attributes = disk.split("  ")
        attributes.each do |attr|
          name = attr.chomp.split(":").last.strip if attr.include?("logical name")
          capacity = attr.chomp.split(":").last.split(" ").last.strip if attr.include?("size:")
          serial = attr.chomp.split(":").last.strip if attr.include?("serial")          
        end
        is_system = system_disks[:devices].include?(name) ? true : false
        is_cache = cache_disks[:devices].include?(name) ? true : false
        #which_raid = system_disks[:raid] if is_system
        #which_raid = cache_disks[:raid] if is_cache
        is_free = is_system or is_cache ? false : true
        partitioned =  is_free ? false : true
        hash = {:name => name, :capacity => capacity, :serial => serial, :system => is_system, :cache => is_cache, :free => is_free, :partitioned => partitioned, :clean_partition => is_free}
        scan_for_other_uses(hash)
        hash[:raid] = `cat /proc/mdstat | grep "#{hash[:name].split('/').last}"`.chomp.split.first
        disks[name] = hash
      end
    end
    disks
  end

  def self.scan_for_other_uses(hash)
  end

  def self.used_for_system
    self.disk_usage("on / ")
  end

  def is_system_disk?
    system "mount | grep '#{name}.*on / '"
  end

  def self.used_for_cache
    hash = {:raid => nil, :devices => []}
    devs = self.disk_usage("/mnt/sequreisp/dev")
    if devs[:devices].empty?
      devs = self.disk_usage("/mnt/cache")
      devs = self.disk_usage("/mnt/cache/web") if devs[:devices].empty?
      hash[:devices] = devs[:devices]
    else
      devs[:devices].each do |dev|
        hash[:devices] << dev if File.directory?("/mnt/sequreisp#{dev}/squid")
      end
    end
    hash[:raid] = devs[:raid]
    hash
  end

  def self.disk_usage(command)
    hash = {:raid => nil, :devices => []}
    IO.popen("mount | grep '#{command}'", "r") do |io|
      io.each do |line|
        device = line.chomp.split(" ").first
        if device.include?("md")
          hash[:raid] = device
          IO.popen("cat /proc/mdstat | grep #{device.split("/").last}", "r") do |io|
            io.each do |line|
              _cache_disks = line.chomp.split(" ")
              _cache_disks[4.._cache_disks.count].each do |disk|
                hash[:devices] << "/dev/#{disk[0..2]}"
              end
            end
          end
        else
          hash[:devices] << device.delete(device.last)
        end
      end
    end
    hash
  end

  def assigned_for(attr)
    self.free   = attr.include?(:free) ? true : false
    self.system = attr.include?(:system) ? true : false
    self.cache  = attr.include?(:cache) ? true : false
    self.save
  end

  def name_with_partition
    "#{name}1"
  end
  def mounting_point
    "/mnt/sequreisp#{name}"
  end
  def mount_and_add_to_fstab
    fstab_line = "#{name_with_partition} #{mounting_point} ext4 defaults 0 1"
    if system "grep '#{name_with_partition}' /etc/fstab"
      system "sed -i 's/^#{name_with_partition}.*/#{fstab_line}' /etc/fstab"
    else
      system "echo #{fstab_line} >> /etc/fstab"
    end
    system "mkdir -p #{mounting_point}"
    system "mount #{name_with_partition}"
  end
  def do_prepare_disk_for_cache
    if system?
      system "mkdir -p /var/spool/squid"
      system "chown proxy.proxy -R /var/spool/squid"
    else
      system "mkdir -p #{mounting_point}/squid"
      system "chown proxy.proxy -R #{mounting_point}/squid"
    end
  end
  def umount_and_remove_from_fstab
    system "sed -i '@#{name_with_partition}@d' /etc/fstab"
    system "umount -l #{name_with_partition}"
  end

  def format
    system "dd if=/dev/zero of=#{name} count=1024 bs=1024"
    system "(echo n; echo p; echo 1; echo ; echo ; echo w) | fdisk #{name}"
    system "mkfs.ext4 #{name_with_partition}"
  end

  def self.not_custom_raids_present?
    all(:conditions => 'raid is not NULL and system = 0').count == 0
  end

  def capacity
    dev = raid.present? ? raid : name
    @_capacity ||= `fdisk -l | grep 'Disk #{dev}'"`.first.chomp.split(" ")[4].to_i / (1024 * 1024) * 0.30 #MEGABYTE
  end

  MAX_SQUID_TOTAL_SIZE = 300*1024 #300GB
  MAX_SQUID_ON_SYSTEM_DISK_SIZE = 50 * 1024 #50GB
  def self.cache_dir_lines
    lines = []
    if Disk.not_custom_raids_present?
      # NO RAIDS, whe take CONTROL
      system "sed -i '/^ *cache_dir*/ c #cache_dir ufs \/var\/spool\/squid 30000 16 256' /etc/squid/squid.conf"

      cache_disks = Disk.cache
      if cache_disks.empty?
        disk = Disk.system.first
        disk.do_prepare_disk_for_cache
        # disco sistema: hasta 30% y un tope de 50 GB
        value_for_cache_dir = disk.capacity > MAX_SQUID_ON_SYSTEM_DISK_SIZE ? MAX_SQUID_ON_SYSTEM_DISK_SIZE : disk.capacity
        lines << "cache_dir aufs /var/spool/squid #{value_for_cache_dir.to_i} 16 256"
      else
        #system "rm -rf /var/spool/squid &"
        total_capacity = cache_disks.collect(&:capacity).sum
        cache_disks.each do |disk|
          # disco aparte: hasta 30% proporcional al disco hasta un tope de 300GB TOTAL
          value_for_cache_dir =  total_capacity > MAX_SQUID_TOTAL_SIZE ? (disk.capacity * MAX_SQUID_TOTAL_SIZE / total_capacity) : disk.capacity
          lines << "cache_dir aufs #{mounting_point}/squid #{value_for_cache_dir.to_i} 16 256"
        end
      end
    end
    lines
  end
end
