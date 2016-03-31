# installimage - Generic and automated linux installer

**installimage** is a collection of shell-scripts that can be used to install physical and virtual machines quickly.

---

## Contents
+ [Setup](#setup)
    - [Workflow](#workflow)
    - [installimage.in_screen](#installimage.in_screen)
    - [installimage](#installimage)
    - [config.sh](#config.sh)
    - [functions.sh](#functions.sh)
    - [get_options.sh](#get_options.sh)
    - [autosetup.sh](#autosetup.sh)
    - [setup.sh](setup.sh)
    - [install.sh](#install.sh)
    - [$distro.sh]($distro.sh)
+ [Requirements](#requirements)
+ [Configuration](#configuration)
+ [Usage](#usage)
+ [How does it work](#how-does-it-work)
+ [Issues](#issues)
+ [Styleguide](#styleguide)
+ [Contributor Code of Conduct](#contributor-code-of-conduct)
+ [Copyright and Contributors](#copyright-and-contributors)
    - [Hetzner Online GmbH](#hetzner-online-gmbh)
    - [GitHub Users](#github-users)
    - [Original License](#original-license)
+ [Name origin](#name-origin)

---

## Setup
### Workflow
We've got a small diagram showing the workflow during an installation process:
![installimage-workflow](https://rawgit.com/virtapi/installimage/master/installimage-workflow.svg)

###installimage.in_screen
This is the initial script that gets called if we automatically start the installimage after a boot process. It adjusts the PATH environment variable because the one provided by the live system may not include all needed path that the system has that we install. The script restarts itself in a new screen session if it isn't already running in one. If it is running in a screen session it starts the actual [installimage](#installimage). It reboots the server after the successful installation or drops you into a bash if the installation failed.

###installimage
Here gets the [config.sh](#config.sh) executed to get many needed variables. Existing mounted partitions or active LVM/mdadm volumes will be stopped. It is possible to provide a custom file with varibles to overwrite default ones (for example the prefered hostname, the image to install), the installimage script checks if this custom file is present and sources it, than the unattended installation starts ([autosetup.sh](#autosetup.sh)). Otherwise the [setup.sh](setup.sh) will be called.

###config.sh
The installimage needs a long list of default parameters, most ofthem are defined in the `config.sh`. They are simple bash variables that get exported. The file also executes the [functions.sh](#functions.sh).

###functions.sh
The function is split into three parts:
* define every variable that needs a function to be determind (IPADDR, HWADDR...)
* the functions that fill up the variables (gather_network_information())
* global functions to provision the image (generate_ntp_config())

See also [$distro.sh]($distro.sh)

###get_options.sh
The installimage provides many CLI command options. They are all specified in this file. They get parsed and validated and have some basic logic checks (it is not possible to provide every combination of params, and some require some others). The `get_options.sh` also holds a help message that you can reach by running `installimage -h`.

###autosetup.sh
Every needed variable here will be validated, they are provided by the [config.sh](#config.sh) + a custom file. The actual installation will start afterwords via the [install.sh](#install.sh).

###setup.sh
installimage supports a menu based installation. This happens in the `setup.sh` file. At first you select the operating system you would like to have, than a Midnight Commander pops up with every needed variable for the installation. Some of them are preconfigured because the installimage tries to guess it, for example a working default partitioning scheme. The actual installation will start afterwords via the [install.sh](#install.sh).

###install.sh

###$distro.sh
Some of the global functions don't work on every distribution, so they are overwritten in a distribution-specific file.

---

## Requirements
TBD

---

## Configuration
TBD

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

## Issues
[Github Issues](https://www.github.com/virtapi/installimage/issues)

---

## Styleguide
We defined our own styleguide [here](styleguide-bash.md), this is a work-in-progress style. We discussed all points on IRC, most of them are based on shellcheck suggestions and our own opinion. We update the guide from time to time.

---

## Contributor Code of Conduct
We support the Contributor Covenant, you can find it [here](code_of_conduct.md).

---

## Copyright and Contributors
### Hetzner Online GmbH
* David Mayr
* Markus Schade
* Florian Wicke

### GitHub Users
* [Contributors](https://github.com/virtapi/installimage/graphs/contributors)

### Original License
* [Original License Statement](http://wiki.hetzner.de/index.php/Installimage/en#Who_is_the_author_of_the_script.3F_Can_I_use_it_freely.3F)

---

## Name Origin
**installimage** installs Linux-distributions with the use of images.
