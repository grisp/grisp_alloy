################################################################################
#
# Vagrantfile
#
################################################################################

#VAGRANT_EXPERIMENTAL="disks"

### Change here for more memory/cores ###
VM_MEMORY=16384
VM_CORES=8

# Tells us if the host system is an Apple Silicon Mac running Rosetta
def is_arm64()
  `uname -m` == "arm64" || `/usr/bin/arch -64 sh -c "sysctl -in sysctl.proc_translated"`.strip() == "0"
end


Vagrant.configure('2') do |config|

    required_plugins = %w( vagrant-scp vagrant-exec )
    _retry = false
    required_plugins.each do |plugin|
        unless Vagrant.has_plugin? plugin
            system "vagrant plugin install #{plugin}"
            _retry=true
        end
    end

    if (_retry)
        exec "vagrant " + ARGV.join(' ')
    end

    config.vm.disk :disk, size: "64GB", primary: true

    if is_arm64()
        config.vm.box = "uwbbi/bionic-arm64"
        libc = "libc6:arm64"
        repos = "dpkg --add-architecture arm64
                 dpkg --add-architecture x86-64"
    else
        config.vm.box = "hashicorp/bionic64"
        libc = "libc6:i386"
        repos = "dpkg --add-architecture i386"
    end

    config.vm.provider :vmware_fusion do |v, override|
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
        required_plugins.each do |plugin|
            system "vagrant plugin install #{plugin}" unless Vagrant.has_plugin? plugin
        end
    end

    config.vm.provision 'shell' do |s|
        s.inline = 'echo Setting up machine name'

        config.vm.provider :vmware_fusion do |v, override|
            v.vmx['displayname'] = "Grisp2 Buildroot"
        end

        config.vm.provider :virtualbox do |v, override|
            v.name = "Grisp2 Buildroot"
        end
    end

    config.vm.provision 'shell', privileged: true, inline:
        "sed -i 's|deb http://us.archive.ubuntu.com/ubuntu/|deb mirror://mirrors.ubuntu.com/mirrors.txt|g' /etc/apt/sources.list
        #{repos}
        apt-get -q update
        apt-get purge -q -y snapd lxcfs lxd ubuntu-core-launcher snap-confine
        apt-get -q -y install mc pv build-essential libncurses5-dev \
            git bzr cvs mercurial subversion #{libc} unzip bc \
            bison flex gperf libncurses5-dev texinfo help2man \
            libssl-dev gawk libtool-bin automake lzip python3
        apt-get -q -y autoremove
        apt-get -q -y clean
        update-locale LC_ALL=C"

    config.vm.provision 'file', source: "build-toolchain.sh", destination: "/home/vagrant/build-toolchain.sh"
    config.vm.provision 'file', source: "build-sdk.sh", destination: "/home/vagrant/build-sdk.sh"
    config.vm.provision 'file', source: "build-firmware.sh", destination: "/home/vagrant/build-firmware.sh"
    config.vm.provision 'file', source: "scripts", destination: "/home/vagrant/scripts"
    config.vm.provision 'file', source: "toolchain", destination: "/home/vagrant/toolchain"
    config.vm.provision 'file', source: "system_common", destination: "/home/vagrant/system_common"
    config.vm.provision 'file', source: "system_grisp2", destination: "/home/vagrant/system_grisp2"
    config.vm.synced_folder "artefacts/", "/home/vagrant/artefacts", create: true, type: "nfs"
    config.vm.synced_folder "_cache/", "/home/vagrant/_cache", create: true, type: "nfs"

    config.ssh.forward_agent = true

end
