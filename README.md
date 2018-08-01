# installimage - Generic and automated linux installer

**installimage** is a collection of shell-scripts that can be used to install physical and virtual machines quickly.

---

## Contents
+ [Setup](#setup)
    - [Workflow](#workflow)
    - [installimage.in_screen](#installimagein_screen)
    - [installimage](#installimage)
    - [config.sh](#configsh)
    - [functions.sh](#functionssh)
    - [get_options.sh](#get_optionssh)
    - [autosetup.sh](#autosetupsh)
    - [setup.sh](#setupsh)
    - [install.sh](#installsh)
    - [$distro.sh](#distrosh)
+ [Requirements](#requirements)
+ [Configuration](#configuration)
+ [Usage](#usage)
+ [How does it work](#how-does-it-work)
+ [Styleguide](#styleguide)
+ [Name origin](#name-origin)
+ [Issues](#issues)
+ [Copyright and Contributors](#copyright-and-contributors)
    - [GitHub Users](#github-users)
    - [Original License](#original-license)
+ [Contact](#contact)
+ [Contribution](#contribution)

---

## Setup
### Workflow
We've got a small diagram showing the workflow during an installation process:
![installimage-workflow](https://rawgit.com/virtapi/installimage/master/installimage-workflow.svg)

### installimage.in_screen
This is the initial script that gets called if we automatically start the installimage after a boot process. It adjusts the PATH environment variable because the one provided by the live system may not include all needed paths that the system we install has. The script restarts itself in a new screen session if it isn't already running in one. If it is running in a screen session it starts the actual [installimage](#installimage). It reboots the server after the successful installation or drops you into a bash if the installation failed.

### installimage
Here gets the [config.sh](#configsh) executed to get many needed variables. Existing mounted partitions or active LVM/mdadm volumes will be stopped. It is possible to provide a custom file with varibles to overwrite default ones (for example the prefered hostname, the image to install), the installimage script checks if this custom file is present and sources it, than the unattended installation starts ([autosetup.sh](#autosetupsh)). Otherwise the [setup.sh](setup.sh) will be called.

### config.sh
The installimage needs a long list of default parameters, most of them are defined in the `config.sh`. They are simple bash variables that get exported. The file also executes the [functions.sh](#functionssh).

### functions.sh
The function is split into three parts:
* define every variable that needs a function to be determind (IPADDR, HWADDR...)
* the functions that fill up the variables (gather_network_information())
* global functions to provision the image (generate_ntp_config())

See also [$distro.sh](#distrosh)

### get_options.sh
The installimage provides many CLI command options. They are all specified in this file. They get parsed and validated and have some basic logic checks (it is not possible to provide every combination of params, and some require some others). The `get_options.sh` also holds a help message that you can reach by running `installimage -h`.

### autosetup.sh
Every needed variable here will be validated, they are provided by the [config.sh](#configsh) + a custom file. The actual installation will start afterwards via the [install.sh](#installsh).

### setup.sh
installimage supports a menu based installation. This happens in the `setup.sh` file. At first you select the operating system you would like to have, then a Midnight Commander pops up with every needed variable for the installation. Some of them are preconfigured because the installimage tries to guess it, for example a working default partitioning scheme. The actual installation will start afterwords via the [install.sh](#installsh).

### install.sh
Here the actual installation happens. The script starts with the calculation of every needed step and prints a helpful menu which always shows you the current process, the amount of finished and needed tasks.

### $distro.sh
Some of the global functions don't work on every distribution, so they are overwritten in a distribution-specific file.

---

## Requirements
We currently don't have an exclusive list of all packages needed by the installimage, however our [LARS](https://github.com/virtapi/LARS#lars---live-arch-rescue-system) project holds a list of all [packages](https://github.com/virtapi/LARS/blob/master/packages.both) needed to create an Archlinux live system which is capable of running the installimage.

---

## Configuration
We designed the installimage to be executed from a live environment - a linux system that isn't booted from the local hard disks but from a USB stick or PXE environment. The common setup is to boot a system via PXE and provide two NFS shares, one with the installimage itself and a different one with the images. We use it like this:
* installimage is mounted on `/root/.installimage`
* Images are mounted at `/root/images`

The `.installimage` directory has to hold the root of this git repository, `images` is a flat directory holding all the images:
```bash
# find . -type f -name "*.tar.gz*"
./CentOS-67-32-minimal.tar.gz.sig
./Ubuntu-1404-trusty-64-minimal.tar.gz
./Debian-83-jessie-64-LAMP.tar.gz
./CentOS-67-32-minimal.tar.gz
./Debian-83-jessie-64-minimal.tar.gz
./Ubuntu-1510-wily-64-minimal.tar.gz.sig
./CentOS-67-64-minimal.tar.gz.sig
./Archlinux-2016-64-minmal.tar.gz.sig
./openSUSE-421-64-minimal.tar.gz
./Debian-79-wheezy-64-minimal.tar.gz
./CentOS-67-64-minimal.tar.gz
./CentOS-72-64-minimal.tar.gz
./openSUSE-421-64-minimal.tar.gz.sig
./Debian-79-wheezy-64-minimal.tar.gz.sig
./Ubuntu-1404-trusty-64-minimal.tar.gz.sig
./CentOS-72-64-cpanel.tar.gz
./Debian-83-jessie-64-LAMP.tar.gz.sig
./Ubuntu-1510-wily-64-minimal.tar.gz
./Archlinux-2016-64-minmal.tar.gz
./CentOS-72-64-cpanel.tar.gz.sig
./CentOS-72-64-minimal.tar.gz.sig
./Debian-83-jessie-64-minimal.tar.gz.sig
```

the installimage ships an example configuration file, `config-example.sh`, you've to copy it to `config.sh`.

---

## Usage
```bash
$ installimage ...
```

---

## How does it work
* Installation quickness is achieved through utilization of prepared tar-ball images, which contain a root-filesystem tree. (e.g. the distro specific bootstrap process is skipped.)
* Base-configuration of the newly installed system is supplied through a selection of shell-scripts.

---

## Styleguide
We defined our own styleguide [here](styleguide-bash.md), this is a work-in-progress style. We discussed all points on IRC, most of them are based on shellcheck suggestions and our own opinion. We update the guide from time to time.

---

## Name Origin
__installimage__ installs Linux-distributions with the use of images.

---

## Issues
[Github Issues](https://www.github.com/virtapi/installimage/issues)

---

## Copyright and Contributors
Hetzner Online GmbH started this project on their own as free software. This project here is based on their work but not associated with Hetzner. We try to keep a list of all authors and contributors in our [LICENSE](LICENSE.md).

### GitHub Users
github.com is so nice to provide us a live list of all [Contributors](https://github.com/virtapi/installimage/graphs/contributors) to this repository.

### Original License
* [Original License Statement](http://wiki.hetzner.de/index.php/Installimage/en#Who_is_the_author_of_the_script.3F_Can_I_use_it_freely.3F)

---

## Contact
You can meet us in #virtapi at freenode.

---

## Contribution
We've defined our contribution rules in [CONTRIBUTING.md](CONTRIBUTING.md).
