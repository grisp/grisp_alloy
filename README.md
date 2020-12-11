# Grisp Linux Builder

## Prerequisites

### Linux

Install the following packages:

```sh
$ sudo apt install build-essential libncurses5-dev \
                pv git bzr cvs mercurial subversion libc6:i386 unzip bc \
                bison flex gperf libncurses5-dev texinfo help2man \
                libssl-dev gawk libtool-bin automake lzip python3
```

### OSX

OSX is not supported natively, a Vagrant VM must be used.

```sh
$ VAGRANT_EXPERIMENTAL="disks" vagrant up
```


## Build Toolchain

### Linux

```sh
$ ./build-toolchain.sh TARGET
```

### OSX

```sh
$ vagrant exec /home/vagrant/build-toolchain.sh TARGET
```


## Build SDK

The toolchain must have been built previously.

### Linux

```sh
$ ./build-sdk.sh TARGET
```

### OSX

```sh
$ vagrant exec /home/vagrant/build-sdk.sh TARGET
```


## Build Firware Update

Both the toolchain and the sytem must have been built previously.

### Linux

```sh
$ ./build-firmware.sh PATH_TO_ERLANG_APP
```

### OSX

**TODO**