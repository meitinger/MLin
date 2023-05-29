# MLin - Minimal Linux Guest OS for Hyper-V


## Description
MLin is a toolkit for creating Hyper-V Gen2 bootable ISO images containing
a minimal Linux distribution. Its package management allows for building
everything from source, and/or collecting existing files.

This means you can either
- build everything statically,
- use dynamic builds and collect existing dependencies like `libc.so` from the
  build system, or
- install everything using the package manager of the build system and collect
  pre-built files only.

The Linux kernel for the image, however, always has to be built from source.
All other files are put into an `initramfs.cpio`, which gets compiled into the
kernel. The resulting ISO image therefore only contains one file, the kernel,
stored in an EFI partition as `/EFI/BOOT/BOOTX64.EFI`.

In addition to defining packages, the toolkit supports multiple image flavors.
A flavor specifies what goes into its `initramfs.cpio`, that is the required
packages as well as any additional files to collect (most commonly the
contents of `/etc`).

For simple variants, for example having the same configuration files but with
different values in each image, it is not necessary to specify multiple
flavors. Instead, the toolkit supports defining multiple variable files that
contain simple `key=value` pairs. Per such file, one image is build where all
flavor-collected files have been transformed by variable substitution.


## Benefits

The primary use case for this distribution is deploying a single-purpose VM.
As such, it has the following advantages:

- Incredible fast boot: Usually it takes longer for Hyper-V to open and
  display the VM window than the boot process itself to complete.
- Immutable images: Since no `vhdx` is required, no adversarial changes can be
  persisted. A reboot will always reset everything.
- Minimal memory footprint: The sample image requires around 80MB of RAM.
- Severely reduced attack surface: The (sample) packages and flavor neither
  contain a shell nor any standard binary utils except those necessary.
  Additionally, the kernel and all other packages are compiled according to
  [KSPP recommendations](https://kernsec.org/wiki/index.php/Kernel_Self_Protection_Project/Recommended_Settings)
  and [Ubuntu's ToolChain compiler flags](https://wiki.ubuntu.com/ToolChain/CompilerFlags).


## Requirements

In order to build any kernel and ISO image, the following packages must be
installed: `sudo apt install build-essential flex bison bc libelf-dev mtools`
The kernel must be configured with `CONFIG_EFI_STUB` in order to be bootable,
and Hyper-V related flags should be enabled as well.
