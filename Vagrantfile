################################################################################
#
# Vagrantfile
#
################################################################################

require 'rbconfig'

VM_PRIMARY_DISK_SIZE = (ENV['VM_PRIMARY_DISK_SIZE']&.strip)
VALID_DISK_SIZE = /\A\d+\s*(KB|MB|GB|TB)\z/i
if VM_PRIMARY_DISK_SIZE && VM_PRIMARY_DISK_SIZE !~ VALID_DISK_SIZE
  abort "VM_PRIMARY_DISK_SIZE must look like '96GB' or '98304MB' (got: #{VM_PRIMARY_DISK_SIZE.inspect})"
end
VM_MEMORY = ENV.fetch('VM_MEMORY', 16 * 1024)   # MB
VM_CORES  = ENV.fetch('VM_CORES', 8).to_i
CACHE_DISK_SIZE = ENV.fetch('VM_CACHE_DISK_SIZE', '10240').to_i
CACHE_DISK_BASENAME = ".vagrant.cache"
CACHE_DISK_LABEL = "VAGRANT_CACHE"
CACHE_DISK_DUMMY_LABEL = "TMPCACHE"

def is_arm64?; RbConfig::CONFIG['host_cpu'] == 'arm64'; end

def host_os
  RbConfig::CONFIG['host_os']
end

def host_platform
  case host_os
  when /darwin/
    :macos
  when /linux/
    :linux
  else
    raise "Unsupported host OS: #{host_os}"
  end
end

def ensure_vagrant_cache_disk
  cache_path = File.expand_path("#{CACHE_DISK_BASENAME}.vmdk", __dir__)
  cache_size = "#{CACHE_DISK_SIZE}M"

  return cache_path if File.exist?(cache_path)

  puts "Creating #{CACHE_DISK_SIZE}MB #{CACHE_DISK_BASENAME}.vmdk..."

  case host_platform
    when :linux
        unless system("qemu-img create -f vmdk '#{cache_path}' #{cache_size}")
            raise "Failed to create VMDK cache disk image"
        end
        unless system("mkfs.ext4 -F -L #{CACHE_DISK_LABEL} '#{cache_path}'")
            raise "Failed to format cache disk with ext4"
        end
    when :macos
        raw_path = File.expand_path("#{CACHE_DISK_BASENAME}.raw", __dir__)
        unless system("dd if=/dev/zero of='#{raw_path}' bs=1m count=#{CACHE_DISK_SIZE}")
            raise "Failed to create raw cache disk image"
        end
        attach_output = `hdiutil attach -imagekey diskimage-class=CRawDiskImage -nomount '#{raw_path}' 2>&1`
        disk_dev = attach_output[/\/dev\/disk\d+/]
        unless disk_dev
            raise "Failed to attach raw image: #{attach_output}"
        end
        begin
            system("newfs_msdos -F 32 -v #{CACHE_DISK_DUMMY_LABEL} #{disk_dev}") or
                raise "Failed to format attached cache disk with FAT32"
        ensure
        system("hdiutil detach #{disk_dev}")
        end
        unless system("qemu-img convert -f raw -O vmdk '#{raw_path}' '#{cache_path}'")
            raise "Failed to convert raw cache disk image to VMDK"
        end
        File.delete(raw_path) if File.exist?(raw_path)
    else
        raise "Unsupported host platform: #{host_platform}"
  end

  unless File.exist?(cache_path)
    raise "Cache disk image not found after creation: #{cache_path}"
  end

  cache_path
end

def register_vmdk_for_virtualbox(path)
    unless File.exist?(path)
        raise "VMDK file #{path} not found on disk"
    end
    if system("VBoxManage showmediuminfo '#{path}' > /dev/null 2>&1")
        return
    end
    puts "Registering #{path} as VirtualBox medium..."
    unless system("VBoxManage openmedium disk '#{path}' --format VMDK")
        raise "Failed to register VMDK disk with VirtualBox (see VBoxManage output above)"
    end
end

CACHE_DISK_PATH = ensure_vagrant_cache_disk

Vagrant.configure('2') do |config|

    required_plugins = %w( vagrant-scp vagrant-exec )
    config.vm.box = "bento/ubuntu-24.04"

    if VM_PRIMARY_DISK_SIZE
        config.vm.disk :disk, size: VM_PRIMARY_DISK_SIZE, primary: true
    end

    if is_arm64?()
        libc_package = "libc6:arm64"
        arch_commands = "dpkg --add-architecture arm64"
        gcc_package = "gcc-x86-64-linux-gnu"
    else
        libc_package = ""
        arch_commands = "dpkg --add-architecture amd64"
        gcc_package = "gcc-x86-64-linux-gnu"
    end

    config.vm.provider :vmware_desktop do |v, override|
        v.gui  = false
        v.linked_clone = false
        v.vmx["ethernet0.virtualDev"]     = "vmxnet3"
        v.vmx["ethernet0.pcislotnumber"]  = "160"
        v.vmx['memsize']  = VM_MEMORY
        v.vmx['numvcpus'] = VM_CORES

        if is_arm64?
          # Use NVMe for every Arm guest OS.
          v.vmx["nvme0.present"]       = "TRUE"
          v.vmx["nvme0:0.present"]     = "TRUE"
          v.vmx["nvme0:0.fileName"]    = CACHE_DISK_PATH
          v.vmx["nvme0:0.mode"]        = "persistent"
        else
          # Keep high-performance PVSCSI controllers on Intel hosts.
          v.vmx["scsi0.virtualDev"]    = "pvscsi"
          v.vmx["scsi1.virtualDev"]    = "pvscsi"
          v.vmx["scsi1.present"]       = "TRUE"
          v.vmx["scsi1:0.present"]     = "TRUE"
          v.vmx["scsi1:0.fileName"]    = CACHE_DISK_PATH
          v.vmx["scsi1:0.mode"]        = "persistent"
        end
      end

    config.vm.provider :virtualbox do |v, override|
        v.memory = VM_MEMORY
        v.cpus = VM_CORES
        required_plugins = %w( vagrant-vbguest )

        if ENV['VAGRANT_DEFAULT_PROVIDER'] == 'virtualbox' || ARGV.any? { |arg| arg.include?('virtualbox') }
            register_vmdk_for_virtualbox(CACHE_DISK_PATH)
        end

        # Attach the cache disk (SATA Port 1)
        v.customize ['storagectl', :id, '--name', 'SATA Controller', '--add', 'sata']
        v.customize ['storageattach', :id, '--storagectl', 'SATA Controller',
                     '--port', 1, '--device', 0, '--type', 'hdd',
                     '--medium', CACHE_DISK_PATH]
    end

    config.vm.provision 'shell' do |s|
        s.inline = 'echo Setting up machine name'

        config.vm.provider :vmware_desktop do |v, override|
            v.vmx['displayname'] = "Grisp2 Buildroot"
        end

        config.vm.provider :virtualbox do |v, override|
            v.name = "Grisp2 Buildroot"
        end
    end

    config.vm.provision 'shell',
      name: 'upgrade_system',
      privileged:  true,
      run: 'once',
      privileged: true,
      inline: <<-SHELL
        if [ -t 1 ]; then
            trap 'tput cnorm 2>/dev/null || printf "\e[?25h" 2>/dev/null || true' EXIT
        elif [ -t 0 ]; then
            stty sane 2>/dev/null || true
        fi
        set -euo pipefail
        export DEBIAN_FRONTEND=noninteractive

        CACHE_MOUNTPOINT="/home/vagrant/_cache"
        CACHE_DISK_LABEL="#{CACHE_DISK_LABEL}"
        CACHE_DISK_DUMMY_LABEL="#{CACHE_DISK_DUMMY_LABEL}"
        mkdir -p "${CACHE_MOUNTPOINT}"

        CACHE_DISK_DEV=$(blkid -L "${CACHE_DISK_LABEL}" || true)

        if [ -z "${CACHE_DISK_DEV}" ]; then
            echo "No ext4 cache disk found, looking for dummy FAT disk..."
            CACHE_DUMMY_DISK_DEV=$(blkid -L "${CACHE_DISK_DUMMY_LABEL}" || true)

            if [ -z "${CACHE_DUMMY_DISK_DEV}" ]; then
                echo "ERROR: No disk labeled ${CACHE_DISK_LABEL} or ${CACHE_DISK_DUMMY_LABEL} found!"
                lsblk
                exit 1
            fi

            echo "Reformatting ${CACHE_DUMMY_DISK_DEV} as ext4 with label ${CACHE_DISK_LABEL}..."
            mkfs.ext4 -F -L "${CACHE_DISK_LABEL}" "${CACHE_DUMMY_DISK_DEV}"
            CACHE_DISK_DEV="${CACHE_DUMMY_DISK_DEV}"
        fi

        # Ensure persistent mount
        if ! grep -qs "LABEL=${CACHE_DISK_LABEL}" /etc/fstab; then
            echo "LABEL=${CACHE_DISK_LABEL} ${CACHE_MOUNTPOINT} ext4 defaults 0 2" >> /etc/fstab
        fi

        mountpoint -q "${CACHE_MOUNTPOINT}" || mount "${CACHE_MOUNTPOINT}"

        chown vagrant:vagrant "${CACHE_MOUNTPOINT}"

        echo 'Acquire::ForceIPv4 "true";' | tee /etc/apt/apt.conf.d/99force-ipv4
        sed -i 's|http://|https://|g' /etc/apt/sources.list

        #{arch_commands}

        apt-get -o Acquire::Retries=3 update
        apt-get -y -q \
            -o Dpkg::Progress-Fancy=0 \
            -o Dpkg::Options::="--force-confdef" \
            -o Dpkg::Options::="--force-confold" \
            full-upgrade
        apt-get -y -q \
            -o Dpkg::Progress-Fancy=0 \
            autoremove --purge
        apt-get clean
    SHELL

    config.vm.provision 'shell',
      name: 'install_packages',
      privileged: true,
      inline: <<-SHELL
        if [ -t 1 ]; then
            trap 'tput cnorm 2>/dev/null || printf "\e[?25h" 2>/dev/null || true' EXIT
        elif [ -t 0 ]; then
            stty sane 2>/dev/null || true
        fi
        set -euo pipefail
        export DEBIAN_FRONTEND=noninteractive

        apt-get -y -q \
            -o Dpkg::Progress-Fancy=0 \
            purge snapd lxd
        apt-get -y -q \
            -o Dpkg::Progress-Fancy=0 \
            -o Dpkg::Options::="--force-confdef" \
            -o Dpkg::Options::="--force-confold" \
            install \
            mc pv libncurses5-dev squashfs-tools \
            git bzr cvs mercurial subversion #{libc_package} unzip bc \
            build-essential bison flex gperf libncurses5-dev texinfo help2man \
            libssl-dev gawk libtool-bin automake lzip python3 wget curl \
            ca-certificates mtools u-boot-tools git-lfs keyutils qemu-user \
            qemu-user-static #{gcc_package} binutils-x86-64-linux-gnu \
            binutils-x86-64-linux-gnu-dbg
        apt-get -y -q \
            -o Dpkg::Progress-Fancy=0 \
            autoremove
        apt-get clean
        update-locale LC_ALL=C
        mkdir -p /opt/grisp_alloy_sdk
        chown -R vagrant:vagrant /opt/grisp_alloy_sdk
    SHELL

    config.vm.provision 'file', source: "build-toolchain.sh", destination: "/home/vagrant/build-toolchain.sh"
    config.vm.provision 'file', source: "build-sdk.sh", destination: "/home/vagrant/build-sdk.sh"
    config.vm.provision 'file', source: "build-firmware.sh", destination: "/home/vagrant/build-firmware.sh"
    config.vm.provision 'file', source: "scripts", destination: "/home/vagrant/scripts"
    config.vm.provision 'file', source: "toolchain", destination: "/home/vagrant/toolchain"
    config.vm.provision 'file', source: "system_common", destination: "/home/vagrant/system_common"
    config.vm.provision 'file', source: "system_grisp2", destination: "/home/vagrant/system_grisp2"
    config.vm.provision 'file', source: "system_kontron-albl-imx8mm", destination: "/home/vagrant/system_kontron-albl-imx8mm"

    config.vm.provider :vmware_desktop do |v, override|
        # On MacOS, NFS sometimes freezes, use vmware GHFS instead.
        override.vm.synced_folder "artefacts/", "/home/vagrant/artefacts", create: true
    end

    config.vm.provider :virtualbox do |v, override|
        override.vm.synced_folder "artefacts/", "/home/vagrant/artefacts", create: true, type: "nfs", nfs_version: 3, nfs_udp: false, mount_options: ['vers=3,tcp']
    end

    config.ssh.forward_agent = true
end
