# installimage

**installimage** is a collection of shell-scripts that can be used to install physical and virtual machines quickly.

---

## Contents
+ [Setup](#setup)
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
We've got a small diagram showing the workflow during an installation process:
![installimage-workflow](https://rawgit.com/virtapi/installimage/add-workflow/installimage-workflow.svg)

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
