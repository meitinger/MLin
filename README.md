# MLin - A minimal router guest OS for Hyper-V.

## Build Instructions

MLin is build from source by executing the PowerShell script `MLin.ps1`.
The script requires the source tarballs for

- [Linux](https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.13.5.tar.xz)
- [BusyBox](https://busybox.net/downloads/busybox-1.33.1.tar.bz2)
- [iptables](https://www.netfilter.org/pub/iptables/iptables-1.8.7.tar.bz2)

in the `-SourceDir`, which defaults to the directory the script is located in.

In addition, [WSL](https://docs.microsoft.com/en-us/windows/wsl/install-win10)
needs to be installed. In case you have multiple WSL distributions installed,
you can select the one to be used by providing the `-Distribution` argument.
(Run `wsl --list` to get a list of names.)

The output VHDX file is placed in the script's directory using the script's
file name (with the extension `.vhdx`), unless `-TargetFile` is specified.

## Characteristics

MLin uses the smallest set of features from BusyBox and the Linux kernel
necessary to accomplish its tasks. These features are selected in the kconfig
files `busybox.config` and `linux.config`, which, of course, can be extended
if needed. Currently everything required for Hyper-V networking, a DHCP
server, routing and iptables with NATting is enabled.

Mlin builds a static executable of BusyBox and IPTables and buts them into an
initramfs together with the configuration files in `etc`. The list of files is
described in `initramfs.list`. Again, this list can be extended or altered, as
can the configuration files in `etc`.

The initramfs is then compressed using LZMA and built into the kernel binary.
The binary itself is EFI stub enabled, which allows it to be booted by Hyper-V
directly, without any bootloader like GRUB or Syslinux.

Finally, the script creates a virtual hard disk file with just one, small EFI
partition and places the kernel binary into that partition.

The VM (generation 2) needs to be created by the user. In theory the kernel
binary could be signed, but in practise it's easier to just disable the Secure
Boot feature for the VM.

The OS requires almost no memory (128MB should be enough) and boots up almost
instantly.

## Templating

There is also an option to specify `-TargetDir` and `-TemplateFile`
instead of `-TargetFile`.
This allows to create multiple VHDXs files based on replacing strings in the
form of `<NAME>` in all files within the `etc` directory before placing them
in the initramfs.

The strings and VHDX file names are specified in a CSV file, whose path is
provided in the `-TemplateFile` argument.
The following is an example that builds two files, `ROUTER-INN.vhdx` and
`ROUTER-VIE.vhdx`, by replacing `<IP>` and `<DN>` strings in their
configuration files with given values:

```csv
Name;ROUTER-INN;ROUTER-VIE
IP;10.0.10.1;10.0.20.1
DN;innsbruck.local;vienna.local
```
