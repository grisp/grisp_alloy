################################################################################
#
# Vagrantfile
#
################################################################################

VM_MEMORY = ENV.fetch('VM_MEMORY', 16 * 1024)   # MB
VM_CORES  = ENV.fetch('VM_CORES', 8).to_i

def is_arm64?; RbConfig::CONFIG['host_cpu'] == 'arm64'; end

Vagrant.configure('2') do |config|

    required_plugins = %w( vagrant-scp vagrant-exec )
    config.vm.box = "bento/ubuntu-24.04"
    config.vm.disk :disk, size: 64 * 1024, primary: true

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
        v.gui = true
        v.vmx["ethernet0.virtualDev"] = "vmxnet3"
        v.vmx["ethernet0.pcislotnumber"] = "160"
        v.vmx["scsi0.virtualDev"] = "pvscsi"
        v.vmx['memsize'] = VM_MEMORY
        v.vmx['numvcpus'] = VM_CORES
    end

    config.vm.provider :virtualbox do |v, override|
        v.memory = VM_MEMORY
        v.cpus = VM_CORES
        required_plugins = %w( vagrant-vbguest )
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
        set -euo pipefail
        export DEBIAN_FRONTEND=noninteractive

        echo 'Acquire::ForceIPv4 "true";' | tee /etc/apt/apt.conf.d/99force-ipv4
        sed -i 's|http://|https://|g' /etc/apt/sources.list

        #{arch_commands}

        apt-get -o Acquire::Retries=3 update
        apt-get -y -q \
          -o Dpkg::Options::="--force-confdef" \
          -o Dpkg::Options::="--force-confold" \
          full-upgrade

        apt-get autoremove -yq --purge
        apt-get clean
    SHELL

    config.vm.provision 'shell',
      name: 'install_packages',
      privileged: true,
      inline: <<-SHELL
        apt-get purge -q -y snapd lxd
        apt-get -o APT::Frontend=noninteractive \
                -o Dpkg::Options::="--force-confdef" \
                -o Dpkg::Options::="--force-confold" \
                -y -q install  \
            mc pv libncurses5-dev squashfs-tools \
            git bzr cvs mercurial subversion #{libc_package} unzip bc \
            build-essential bison flex gperf libncurses5-dev texinfo help2man \
            libssl-dev gawk libtool-bin automake lzip python3 wget curl \
            ca-certificates mtools u-boot-tools git-lfs keyutils qemu-user \
            qemu-user-static #{gcc_package} binutils-x86-64-linux-gnu \
            binutils-x86-64-linux-gnu-dbg
        apt-get -q -y autoremove
        apt-get -q -y clean
        update-locale LC_ALL=C
        mkdir -p /opt/grisp_linux_sdk
        chown -R vagrant:vagrant /opt/grisp_linux_sdk
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
        override.vm.synced_folder "_cache/", "/home/vagrant/_cache", create: true
    end

    config.vm.provider :virtualbox do |v, override|
        override.vm.synced_folder "artefacts/", "/home/vagrant/artefacts", create: true, type: "nfs", nfs_version: 3, nfs_udp: false, mount_options: ['vers=3,tcp']
        override.vm.synced_folder "_cache/", "/home/vagrant/_cache", create: true, type: "nfs", nfs_version: 3, nfs_udp: false, mount_options: ['vers=3,tcp']
    end

    config.ssh.forward_agent = true
end
