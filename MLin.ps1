# Copyright (C) 2021 Manuel Meitinger
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

[CmdletBinding(DefaultParameterSetName='SingleFile')]
Param (
    [string] $SourceDir = $PSScriptRoot,
    [string] $StageDir,
    [Parameter(ParameterSetName='SingleFile')][string] $TargetFile = ([System.IO.Path]::ChangeExtension($PSCommandPath, '.vhdx')),
    [version] $KernelVersion,
    [version] $BusyBoxVersion,
    [version] $IPTablesVersion,
    [Parameter(ParameterSetName='MultipleFiles')][string] $TargetDir = $PSScriptRoot,
    [Parameter(Mandatory=$true, ParameterSetName='MultipleFiles')][string] $TemplateFile,
    [string] $Distribution,
    [ValidateRange(1,255)][byte] $Threads = 4,
    [switch] $Force
)


Set-StrictMode -Version Latest
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)


Function Invoke-WSL {
    Param (
        [Parameter(Mandatory=$true, ParameterSetName='Command')][string] $Command,
        [Parameter(Mandatory=$true, ParameterSetName='Batch')][object[]] $Batch,
        [Parameter(Mandatory=$true, ParameterSetName='Batch')][string] $BatchName
    )

    $IsBatch = $PSCmdlet.ParameterSetName -eq 'Batch'
    If ($IsBatch) {
        Write-Progress -Activity $BatchName -PercentComplete 0
    }
    Else {
        $Batch = @($Command)
    }
    $Completed = 0
    ForEach ($Task In $Batch) {
        If ($IsBatch) {
            Write-Progress -Activity $BatchName -CurrentOperation $Task -PercentComplete ($Completed++ * 100 / $Batch.Count)
        }
        If ($Task -is [string]) {
            Write-Verbose -Message "Executing command '$Task'."
            & {
                $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Continue
                If ($Script:PSBoundParameters.ContainsKey('Distribution')) {
                    & 'wsl.exe' --distribution $Script:Distribution -- eval $Task
                }
                Else {
                    & 'wsl.exe' wsl.exe -- eval $Task
                }
            }
            If ($LASTEXITCODE -ne 0) {
                Write-Error -Message "Command '$Task' failed with error code $LASTEXITCODE."
            }
        }
        ElseIf ($Task -is [scriptblock]) {
            & $Task
        }
        Else {
            Write-Error -Message "Unsupported command type '$($Task.GetType())'."
        }
    }
    If ($IsBatch) {
        Write-Progress -Activity $BatchName -PercentComplete 100 -Completed
    }
}


Function ConvertTo-LinuxPath {
    Param ([Parameter(Mandatory=$true)][string] $Path)

    Return (Invoke-WSL -Command "printf '%q' \`"`$(wslpath -au '$($Path.Replace("'","'\\''"))')\`"")
}


Function ConvertTo-WindowsPath {
    Param ([Parameter(Mandatory=$true)][string] $Path)

    Return (Invoke-WSL -Command "wslpath -aw $Path")
}


Function Merge-BusyBoxConfig {
    Param (
        [Parameter(Mandatory=$true)][string] $Path,
        [Parameter(Mandatory=$true)][string] $TemplatePath
    )

    $Template = @{}
    Switch -Regex -CaseSensitive -File $TemplatePath {
        '^(# )?CONFIG_(?<name>[A-Z0-9]+(_[A-Z0-9]+)*)(=(?<value>.*)| is not set)$' {
            $SymbolName = $Matches['name']
            If ($Template.ContainsKey($SymbolName)) {
                Write-Warning -Message "Duplicate symbol '$SymbolName' in template file '$TemplatePath'."
            }
            $Template[$SymbolName] = $Matches['value']
        }
        '^(#|$)' {
            # ignored
        }
        Default {
            Write-Error -Message "Invalid line '$_' in template file '$TemplatePath'."
        }
    }
    Write-Verbose -Message "Using $($Template.Count) configurations from template file '$TemplatePath'."

    $NewConfig = Switch -Regex -CaseSensitive -File $Path {
        '^(# )?CONFIG_(?<name>[A-Z0-9]+(_[A-Z0-9]+)*)(=| is not set)' {
            $SymbolName = $Matches['name']
            If ($Template.ContainsKey($SymbolName)) {
                $Value = $Template[$SymbolName]
                Write-Verbose -Message "Replacing CONFIG_$SymbolName in config file '$Path'."
                If ($Value -eq $null) {
                    "# CONFIG_$SymbolName is not set"
                }
                Else {
                    "CONFIG_$SymbolName=$Value"
                }
            }
            Else {
                $_
            }
        }
        '^(#|$)' {
            # ignored
        }
        Default {
            Write-Error -Message "Invalid line '$_' in config file '$Path'."
        }
    }

    [System.IO.File]::WriteAllText($Path, ($NewConfig -join "`n"), $Script:Utf8NoBom)
}


Function New-EfiBootVhd {
    Param (
        [Parameter(Mandatory=$true)][string] $Path,
        [Parameter(Mandatory=$true)][string] $KernelPath
    )

    $Size = (Get-Item -LiteralPath $KernelPath).Length + 1MB
    $Size = [System.Math]::Max(3MB, $Size + (1MB - $Size % 1MB))
    Write-Verbose "Creating VHD of $Size bytes."

    $Vhd = New-VHD -Path $Path -SizeBytes $Size -Fixed
    Try {
        $MountedVhd = $vhd | Mount-VHD -NoDriveLetter -Passthru
        Try {
            $MountedVhd | Initialize-Disk -PartitionStyle GPT
            $EfiPartition = $MountedVhd | New-Partition -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -UseMaximumSize
            $EfiVolume = $EfiPartition | Format-Volume -FileSystem FAT -NewFileSystemLabel 'EFI'
            Write-Verbose -Message "Using target volume '$($EfiVolume.Path)'."

            $TargetDir = Join-Path -Path $EfiVolume.Path -ChildPath 'EFI\BOOT'
            New-Item -ItemType Directory -Path $TargetDir | Out-Null
            Copy-Item -LiteralPath $KernelPath -Destination (Join-Path -Path $TargetDir -ChildPath 'BOOTX64.EFI')
        }
        Finally {
            $Vhd | Dismount-VHD
        }
    }
    Catch {
        Remove-Item -LiteralPath $Path -Force
        Throw
    }
}


Function Get-VersionedResource {
    Param (
        [Parameter(Mandatory=$true)][string] $SourceDir,
        [Parameter(Mandatory=$true)][string] $Prefix,
        [Parameter(Mandatory=$true)][string] $Extension,
        [version] $Version
    )

    If (-not $Version) {
        $Filter = "$Prefix*$Extension"
        $Versions = (Get-ChildItem -LiteralPath $SourceDir -Filter $Filter) | ForEach-Object -Process {
            $VersionString = $_.Name.Substring($Prefix.Length, $_.Name.Length - ($Prefix.Length + $Extension.Length))
            If ([version]::TryParse($VersionString, [ref]$Version)) {
                Return ($Version)
            }
        } | Sort-Object
        If (-not $Versions) {
            Write-Error -Message "No file matching '$Filter' found in '$SourceDir'."
        }
        $Version = $Versions[-1]
    }
    Else {
        $FilePath = Join-Path -Path $SourceDir -ChildPath "$Prefix$Version$Extension"
        If (-not (Test-Path -PathType Leaf -LiteralPath $FilePath)) {
            Write-Error -Message "File '$FilePath' doesn't exist."
        }
    }
    Write-Verbose -Message "Using file '$Prefix$Version$Extension'."
    Return ("$Prefix$Version")
}


Function Get-TemplateStrings {
    Param ([Parameter(Mandatory=$true)][string] $Path)

    $Result = @{}
    $CsvFile = Import-Csv -Delimiter `; -LiteralPath $Path
    ForEach ($Entry In $CsvFile) {
        $StringName = $Entry.Name
        $TemplateNames = $Entry | Get-Member -MemberType NoteProperty | Where-Object -Property 'Name' -NE -Value 'Name' | Select-Object -ExpandProperty 'Name'
        ForEach ($TemplateName In $TemplateNames) {
            If ($Result.ContainsKey($TemplateName)) {
                $Strings = $Result[$TemplateName]
            }
            Else {
                $Result[$TemplateName] = $Strings = @{}
            }
            If ($Strings.ContainsKey($StringName)) {
                Write-Warning -Message "Duplicate string '$StringName' for template '$TemplateName' in file '$Path'."
            }
            $Strings[$StringName] = $Entry.$TemplateName
        }
        Write-Verbose -Message "Replacing <$StringName> strings in configuration files."

    }
    Return ($Result)
}


Function Copy-PatchedConfigFiles {
    Param (
        [Parameter(Mandatory=$true)][string] $SourceDir,
        [Parameter(Mandatory=$true)][string] $TargetDir,
        [Parameter(Mandatory=$true)][hashtable] $Replacements
    )

    ForEach ($ConfigFile In Get-ChildItem -LiteralPath $SourceDir) {
        [System.IO.File]::WriteAllText(
            (Join-Path -Path $TargetDir -ChildPath $ConfigFile.Name),
            [regex]::Replace(
                [System.IO.File]::ReadAllText($ConfigFile.FullName, $Script:Utf8NoBom),
                '<(?<Name>[_A-Z][_A-Z0-9]*)>',
                {
                    Param ([System.Text.RegularExpressions.Match] $Match)

                    $StringName = $Match.Groups['Name'].Value
                    If (-not $Replacements.ContainsKey($StringName)) {
                        Write-Error -Message "Replacement for string '$StringName' in file '$ConfigFile' not found."
                    }
                    Return ($Replacements[$StringName])
                },
                [System.Text.RegularExpressions.RegexOptions]::CultureInvariant +
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase +
                [System.Text.RegularExpressions.RegexOptions]::ExplicitCapture
            ),
            $Script:Utf8NoBom
        )
    }
}


Function Test-TargetFileExists {
    Param ([Parameter(Mandatory=$true)][string] $Path)

    If (Test-Path -LiteralPath $Path) {
        If (-not $Script:Force) {
            Throw [System.IO.IOException]::new("File '$Path' already exists.")
        }
        Else {
            Remove-Item -LiteralPath $Path -Force
        }
    }
}


# make sure New-VHD will succeed for single files
If ($PSCmdlet.ParameterSetName -eq 'SingleFile') {
    Test-TargetFileExists -Path $TargetFile
}

# find all required resource files
$Kernel = Get-VersionedResource -SourceDir $SourceDir -Prefix 'linux-' -Extension '.tar.xz' -Version $KernelVersion
$BusyBox = Get-VersionedResource -SourceDir $SourceDir -Prefix 'busybox-' -Extension '.tar.bz2' -Version $BusyBoxVersion
$IPTables = Get-VersionedResource -SourceDir $SourceDir -Prefix 'iptables-' -Extension '.tar.bz2' -Version $IPTablesVersion

# translate paths and create the stage if necessary
$Source = ConvertTo-LinuxPath -Path $SourceDir
If ($PSBoundParameters.ContainsKey('StageDir')) {
    $Stage = ConvertTo-LinuxPath $StageDir
}
Else {
    $Stage = Invoke-WSL -Command "printf '%q' `"`$(mktemp --directory)`""
    $StageDir = ConvertTo-WindowsPath -Path $Stage
}
Write-Verbose -Message "Using stage directory '$StageDir'."

# run all commands
Try {

    Invoke-WSL -BatchName 'IPTables' -Batch @(
        "tar --extract --bzip2 --file=$Source/$IPTables.tar.bz2 --directory=$Stage"
        "cd $Stage/$IPTables && CFLAGS='-ffunction-sections -fdata-sections -Wl,--gc-sections -s' ./configure --prefix=$Stage/$IPTables/build --disable-shared --disable-ipv6 --disable-nftables --disable-largefile"
        "sed --in-place 's/LDFLAGS =/LDFLAGS = -all-static/' $Stage/$IPTables/iptables/Makefile"
        "make --directory=$Stage/$IPTables --jobs=$Threads"
        "make --directory=$Stage/$IPTables install"
    )

    Invoke-WSL -BatchName 'BusyBox' -Batch @(
        "tar --extract --bzip2 --file=$Source/$BusyBox.tar.bz2 --directory=$Stage"
        "mkdir --parent $Stage/$BusyBox/build"
        "make --directory=$Stage/$BusyBox O=$Stage/$BusyBox/build allnoconfig"
        { Merge-BusyBoxConfig -Path "$StageDir\$BusyBox\build\.config" -TemplatePath "$SourceDir\busybox.config" }
        "yes '' | make --directory=$Stage/$BusyBox O=$Stage/$BusyBox/build oldconfig"
        "make --directory=$Stage/$BusyBox O=$Stage/$BusyBox/build --jobs=$Threads"
    )

    Invoke-WSL -BatchName 'Kernel' -Batch @(
        "tar --extract --xz --file=$Source/$Kernel.tar.xz --directory=$Stage"
        "mkdir --parent $Stage/$Kernel/build/usr/bin"
        "cp --force $Source/initramfs.list $Stage/$Kernel/build/usr/"
        "cp --force $Stage/$IPTables/build/sbin/xtables-legacy-multi $Stage/$Kernel/build/usr/bin/"
        "cp --force $Stage/$BusyBox/build/busybox $Stage/$Kernel/build/usr/bin/"
        "cp --archive --force $Source/etc/ $Stage/$Kernel/build/usr/"
        "KCONFIG_ALLCONFIG=$Source/linux.config make --directory=$Stage/$Kernel O=$Stage/$Kernel/build allnoconfig"
        "make --directory=$Stage/$Kernel O=$Stage/$Kernel/build --jobs=$Threads"
    )

    If ($PSCmdlet.ParameterSetName -eq 'SingleFile') {
        New-EfiBootVhd -Path $TargetFile -KernelPath "$StageDir\$Kernel\build\arch\x86\boot\bzImage"
    }
    Else {
        $TemplateStrings = Get-TemplateStrings -Path $TemplateFile
        $Completed = 0
        ForEach ($TemplateString In $TemplateStrings.GetEnumerator()) {
            Write-Progress -Activity 'Generate Virtual Hard Disks' -CurrentOperation $TemplateString.Key -PercentComplete ($Completed++ * 100 / $TemplateStrings.Count)
            $TargetFile = "$TargetDir\$($TemplateString.Key).vhdx"
            Test-TargetFileExists -Path $TargetFile
            Copy-PatchedConfigFiles -SourceDir "$SourceDir\etc" -TargetDir "$StageDir\$Kernel\build\usr\etc" -Replacements $TemplateString.Value
            Invoke-WSL -Command "make --directory=$Stage/$Kernel O=$Stage/$Kernel/build --jobs=$Threads"
            New-EfiBootVhd -Path $TargetFile -KernelPath "$StageDir\$Kernel\build\arch\x86\boot\bzImage"
        }
        Write-Progress -Activity 'Generate Virtual Hard Disks' -PercentComplete 100 -Completed
    }

}

# cleanup the stage if necessary
Finally {

    If (-not $PSBoundParameters.ContainsKey('StageDir')) {
        Invoke-WSL -Command "rm --recursive --force $Stage"
    }

}
