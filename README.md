# MLin - A minimal router guest OS for Hyper-V

## Build Instructions

MLin is build from source by executing the PowerShell script `MLin.ps1`.
The script requires the source tarballs for

- [Linux](https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.13.5.tar.xz)
- [BusyBox](https://busybox.net/downloads/busybox-1.33.1.tar.bz2)
- [iptables](https://www.netfilter.org/pub/iptables/iptables-1.8.7.tar.bz2)

in the `-SourceDir`, which defaults to directory the script is located in.

In addition, [WSL](https://docs.microsoft.com/en-us/windows/wsl/install-win10)
needs to be installed. In case you have multiple WSL distributions installed,
you can select your preferred one using the `-Distribution` argument.

The output VHDX file is placed in the script's directory with the script's
file name, unless `-TargetFile` is specified.

## Characteristics

MLin uses the smallest set of features from BusyBox and the Linux kernel
necessary to accomplish its tasks. These features are selected using the
kconfig files `busybox.config` and `linux.config`, which of course can be
extended if needed. Currently everything needed for Hyper-V networking, a DHCP
server, routing and iptables with NATting is enabled.

Mlin builds a static executable of BusyBox and IPTables and buts them into an
initramfs together with the configuration files in `etc`. The list of files is
described in `initramfs.list`. Again, this list can be extended if needed.

The initramfs is then compressed using LZMA and built into the kernel binary.
The binary itself is EFI stub enabled, which allows it to be booted from
Hyper-V directly, without a bootloader like GRUB or Syslinux.

Finally, the script created a virtual hard disk file (VHDX) with just one,
small EFI partition and places the kernel binary into that partition.

## Templating

There is also an option to specify `-TargetDir` and `-TemplateFile`
instead of `-TargetFile`.
This allows to create multiple VHDXs files based on replacing string in
form of `<NAME>` in all files within the `etc` directory before placing them
in the initramfs.

The strings and VHDX file names are specified in a CSV file, whose path is
provided in `-TemplateFile` argument. The following is an example that builds
two files, `ROUTER-INN.vhdx` and `ROUTER-VIE.vhdx` by replacing `<IP>` and
`<DN>` strings in their configuration files:

```csv
Name;ROUTER-INN;ROUTER-VIE
IP;10.0.10.1;10.0.20.1
DN;innsbruck.local;vienna.local
```
