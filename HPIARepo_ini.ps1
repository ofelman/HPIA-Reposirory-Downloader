<#
    Modify the entries to suite local requirements

    Dan Felman/HP Inc

    7/20/2020

    modify variables as need for use by the Downloader script
#>

$OS = "Win10"
$OSVER = "1909"
$OSVALID = @("1809", "1903", "1909", "2004")

$FilterCategories = @('Driver','BIOS', 'Firmware', 'Software')

#-------------------------------------------------------------------
# Example systems to manage
#
$HPModelsTable = @(
	@{ ProdCode = '8438'; Model = "HP EliteBook x360 1030 G3" }
	@{ ProdCode = '83B3'; Model = "HP ELITEBOOK 830 G5" }
	@{ ProdCode = '844F'; Model = "HP ZBook Studio x360 G5" }
	@{ ProdCode = '83B2'; Model = "HP ELITEBOOK 840 G5" }
	@{ ProdCode = '8549'; Model = "HP ELITEBOOK 840 G6" }
	@{ ProdCode = '8470'; Model = "HP ELITEBOOK X360 1040 G5" }
	@{ ProdCode = '8593'; Model = "HP EliteDesk 800 G5 Desktop Mini PC" }
    @{ ProdCode = '8549'; Model = "HP EliteBook 840 G6 Healthcare Edition" }
    @{ ProdCode = '859F'; Model = "HP EliteOne 800 G5 All-in-One" }
    )

$FileServerName = $Env:COMPUTERNAME 

# choose a path

$RepoShareMain = "\\$($FileServerName)\share\softpaqs\HPIARepo"
#$RepoShareMain = "D:\share\softpaqs\HPIARepo"

$LogFile = "$PSScriptRoot\HPDriverPackDownload.log"               # Default to location where script runs from

# this setting makes the script work with Microsoft SCCM/MECM, if set to $true

$UpdateCMPackages = $False
