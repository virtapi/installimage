# installimage

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


###config.sh

###functions.sh

###get_options.sh

###autosetup.sh

###setup.sh

###install.sh

###$distro.sh

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
