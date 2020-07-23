﻿<#
    HP Image Assistant and Softpaq Repository Downloader
    Version 1.00
    Version 1.10
        added ability to maintain single repository - setting also kept int INI file
        added function to try and import and load HPCMSL powershell module
    Version 1.11
        fix GUI when selecting/deslection All rows checkmark (added call to get_filters to reset categories)
        added form button (at the bottom of the form) to clear textbox
    Version 1.12
        fix interface issues when selecting/deselecting all rows (via header checkmark)
    Versoin 1.15
        added ability for script to use a single common repository, with new variable in INI file
        moved $DebugMode variable to INI file
    Version 1.16
        fixed UI issue switching from single to non-single repository
        Added color coding of which path is in use (single or multiple share repo paths)
#>
param(
	[Parameter(Mandatory = $false,Position = 1,HelpMessage = "Application")]
	[ValidateNotNullOrEmpty()]
	[ValidateSet("sync")]
	$RunMethod = "sync"
)
$ScriptVersion = "1.16 (7/23/2020)"

# get the path to the running script, and populate name of INI configuration file
$scriptName = $MyInvocation.MyCommand.Name
$ScriptPath = Split-Path $MyInvocation.MyCommand.Path

#--------------------------------------------------------------------------------------
$IniFile = "HPIARepo_ini.ps1"                        # assume this INF file in same location as script
$IniFIleFullPath = "$($ScriptPath)\$($IniFile)"

. $IniFIleFullPath                                   # source the code in the INI file      

#--------------------------------------------------------------------------------------
#Script Vars Environment Specific loaded from INI.ps1 file

$CMConnected = $false                                # is a connection to SCCM established?
$SiteCode = $null

#--------------------------------------------------------------------------------------

$TypeError = -1
$TypeNorm = 1
$TypeWarn = 2
$TypeDebug = 4
$TypeSuccess = 5
$TypeNoNewline = 10

#=====================================================================================
#region: CMTraceLog Function formats logging in CMTrace style
function CMTraceLog {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)] $Message,
		[Parameter(Mandatory = $false)] $ErrorMessage,
		[Parameter(Mandatory = $false)] $Component = "HP HPIA Repository Downloader",
		[Parameter(Mandatory = $false)] [int]$Type
	)
	<#
    Type: 1 = Normal, 2 = Warning (yellow), 3 = Error (red)
    #>
	$Time = Get-Date -Format "HH:mm:ss.ffffff"
	$Date = Get-Date -Format "MM-dd-yyyy"

	if ($ErrorMessage -ne $null) { $Type = $TypeError }
	if ($Component -eq $null) { $Component = " " }
	if ($Type -eq $null) { $Type = $TypeNorm }

	$LogMessage = "<![LOG[$Message $ErrorMessage" + "]LOG]!><time=`"$Time`" date=`"$Date`" component=`"$Component`" context=`"`" type=`"$Type`" thread=`"`" file=`"`">"

    #$Type = 4: Debug output ($TypeDebug)
    #$Type = 10: no \newline ($TypeNoNewline)

    if ( ($Type -ne $TypeDebug) -or ( ($Type -eq $TypeDebug) -and $DebugMode) ) {
        $LogMessage | Out-File -Append -Encoding UTF8 -FilePath $Script:LogFile

        # Add output to GUI message box
        OutToForm $Message $Type $Script:TextBox
        
    } else {
        $lineNum = ((get-pscallstack)[0].Location -split " line ")[1]    # output: CM_HPIARepo_Downloader.ps1: line 557
        #Write-Host "$lineNum $(Get-Date -Format "HH:mm:ss") - $Message"
    }

} # function CMTraceLog

#=====================================================================================
<#
    Function OutToForm
        Designed to output message to Form's message box
        it uses color coding of text for different message types
#>
Function OutToForm { 
	[CmdletBinding()]
	param( $pMessage, [int]$pmsgType, $pTextBox)

    switch ( $pmsgType )
    {
       -1 { $pTextBox.SelectionColor = "Red" }                  # Error
        1 { $pTextBox.SelectionColor = "Black" }                # default color is black
        2 { $pTextBox.SelectionColor = "Brown" }                # Warning
        4 { $pTextBox.SelectionColor = "Orange" }               # Debug Output
        5 { $pTextBox.SelectionColor = "Green" }                # success details
        10 { $pTextBox.SelectionColor = "Black" }               # do NOT add \newline to message output
    } # switch ( $pmsgType )

    if ( $pmsgType -eq $TypeDebug ) {
        $pMessage = '{dbg}'+$pMessage
    }

    # message Tpye = 10/$TypeNeNewline prevents a nl so next output is written contiguous

    if ( $pmsgType -eq $TypeNoNewline ) {
        $pTextBox.AppendText("$($pMessage) ")
    } else {
        $pTextBox.AppendText("$($pMessage) `n")
    }
    $pTextBox.Refresh()
    $pTextBox.ScrollToCaret()

} # Function OutToForm

#=====================================================================================
<#
    Function Load_HPModule
        The function will test if the HP Client Management Script Library is loaded
        and attempt to load it, if possible
#>
function Load_HPModule {

    CMTraceLog -Message "> Load_HPModule" -Type $TypeNorm
    $m = 'HPCMSL'

    CMTraceLog -Message "Checking for HP CMSL... " -Type $TypeNoNewline

    # If module is imported say that and do nothing
    if (Get-Module | Where-Object {$_.Name -eq $m}) {
        if ( $DebugMode ) { write-host "Module $m is already imported." }
        CMTraceLog -Message "Module already imported." -Type $TypSuccess
    } else {

        # If module is not imported, but available on disk then import
        if (Get-Module -ListAvailable | Where-Object {$_.Name -eq $m}) {
            if ( $DebugMode ) { write-host "Importing Module $m." }
            CMTraceLog -Message "Importing Module $m." -Type $TypeNoNewline
            Import-Module $m -Verbose
            CMTraceLog -Message "Done" -Type $TypSuccess
        } else {

            # If module is not imported, not available on disk, but is in online gallery then install and import
            if (Find-Module -Name $m | Where-Object {$_.Name -eq $m}) {
                if ( $DebugMode ) { write-host "Upgrading NuGet and updating PowerShellGet first." }
                CMTraceLog -Message "Upgrading NuGet and updating PowerShellGet first." -Type $TypSuccess
                Install-PackageProvider -Name NuGet -ForceBootstrap
                Install-Module -Name PowerShellGet -Force

                if ( $DebugMode ) { write-host "Installing and Importing Module $m." }
                CMTraceLog -Message "Installing and Importing Module $m." -Type $TypSuccess
                Install-Module -Name $m -Force -SkipPublisherCheck -AcceptLicense -Verbose -Scope CurrentUser
                Import-Module $m -Verbose
                CMTraceLog -Message "Done" -Type $TypSuccess
            } else {

                # If module is not imported, not available and not in online gallery then abort
                write-host "Module $m not imported, not available and not in online gallery, exiting."
                CMTraceLog -Message "Module $m not imported, not available and not in online gallery, exiting." -Type $TypError
                exit 1
            }
        } # else if (Get-Module -ListAvailable | Where-Object {$_.Name -eq $m}) 
    } # else if (Get-Module | Where-Object {$_.Name -eq $m})

    CMTraceLog -Message "< Load_HPModule" -Type $TypeNorm

} # function Load_HPModule

#=====================================================================================
<#
    Function Test_CMConnection
        The function will test the CM server connection
        and that the Task Sequences required for use of the Script are available in CM
        - will also test that both download and share paths exist
#>
Function Test_CMConnection {

    CMTraceLog -Message "> Test_CMConnection" -Type $TypeNorm

    if ( $Script:CMConnected ) { return $True }                  # already Tested connection

    $pCurrentLoc = Get-Location

    CMTraceLog -Message "Connecting to CM Server: ""$FileServerName""" -Type $TypeNoNewline
    
    #--------------------------------------------------------------------------------------
    # check for ConfigMan  on this server, and source the PS module

    $boolConnectionRet = $False

    if (Test-Path $env:SMS_ADMIN_UI_PATH) {
        $lCMInstall = Split-Path $env:SMS_ADMIN_UI_PATH
        Import-Module (Join-Path $(Split-Path $env:SMS_ADMIN_UI_PATH) ConfigurationManager.psd1)

        #--------------------------------------------------------------------------------------
        # by now we know the script is running on a CM server and the PS module is loaded
        # so let's get the CMSite content info
    
        Try {
            $Script:SiteCode = (Get-PSDrive -PSProvider CMSite).Name               # assume CM PS modules loaded at this time
            #$RepoShareMain = "\\$($FileServerName)\share\softpaqs\HPIARepo"

            if (Test-Path $lCMInstall) {
        
                try { Test-Connection -ComputerName "$FileServerName" -Quiet

                    CMTraceLog -Message " ...Connected" -Type $TypeSuccess 
                    $boolConnectionRet = $True
                }
                catch {
	                CMTraceLog -Message "Not Connected to File Server, Exiting" -Type $TypeError 
                }
            } else {
                CMTraceLog -Message "CM Installation path NOT FOUND: '$lCMInstall'" -Type $TypeError 
            } # else
        }
        Catch {
            CMTraceLog -Message "Error obtaining CM's CMSite provider on this server" -Type $TypeError
        } # Catch

    } else {
        CMTraceLog -Message "Can't find CM Installation on this system" -Type $TypeError
    }
    CMTraceLog -Message "< Test_CMConnection" -Type $TypeNorm

    Set-Location $pCurrentLoc

    return $boolConnectionRet

} # Function Test_CMConnection

#=====================================================================================
<#
    Function CM_RepoUpdate
#>

Function CM_RepoUpdate {
    [CmdletBinding()]
	param( $pModelName, $pModelProdId, $pRepoPath )                             

    $pCurrentLoc = Get-Location

    CMTraceLog -Message "> CM_RepoUpdate" -Type $TypeNorm
    # develop the Package name
    $lPkgName = 'HP-'+$pModelProdId+'-'+$pModelName
    CMTraceLog -Message "... updating repository for SCCM package: $($lPkgName)" -Type $TypeNorm

    if ( $DebugMode ) { CMTraceLog -Message "... setting location to: $($SiteCode)" -Type $TypeDebug }
    Set-Location -Path "$($SiteCode):"

    if ( $DebugMode ) { CMTraceLog -Message "... getting CM package: $($lPkgName)" -Type $TypeDebug }
    $lCMRepoPackage = Get-CMPackage -Name $lPkgName -Fast

    if ( $lCMRepoPackage -eq $null ) {
        CMTraceLog -Message "... Package missing... Creating New" -Type $TypeNorm
        $lCMRepoPackage = New-CMPackage -Name $lPkgName -Manufacturer "HP"
    }

    #--------------------------------------------------------------------------------
    # update package with info from share folder
    #--------------------------------------------------------------------------------
    if ( $DebugMode ) { CMTraceLog -Message "... setting CM Package to Version: $($OSVER), path: $($pRepoPath)" -Type $TypeDebug }

	Set-CMPackage -Name $lPkgName -Version "$($OSVER)"
	Set-CMPackage -Name $lPkgName -Path $pRepoPath

    CMTraceLog -Message "... updating CM Distribution Points"
    update-CMDistributionPoint -PackageId $lCMRepoPackage.PackageID

    $lCMRepoPackage = Get-CMPackage -Name $lPkgName -Fast                               # make sure we are woring with updated/distributed package

    Set-Location -Path $pCurrentLoc

    CMTraceLog -Message "< CM_RepoUpdate" -Type $TypeNorm

} # Function CM_RepoUpdate

#=====================================================================================
<#
    Function init_repository
        This function will create a repository foldern and initialize it for HPIA, if necessary
        Args:
            $pRepoFOlder: folder to validate, or create
            $pInitRepository: variable - if $true, initialize repository, otherwise, ignore
#>
Function init_repository {
    [CmdletBinding()]
	param( $pRepoFolder,
            $pInitRepository )

    $pCurrentLoc = Get-Location

    CMTraceLog -Message "> init_repository" -Type $TypeNorm

    $retRepoCreated = $false

    if ( (Test-Path $pRepoFolder) -and ($pInitRepository -eq $false) ) {
        $retRepoCreated = $true
    } else {
        $lRepoParentPath = Split-Path -Path $pRepoFolder -Parent        # Get the Parent path to the Main Repo folder

        #--------------------------------------------------------------------------------
        # see if we need to create the path to the folder

        if ( !(Test-Path $lRepoParentPath) ) {
            Try {
                # create the Path to the Repo folder
                New-Item -Path $lRepoParentPath -ItemType directory
                if ( $DebugMode ) { CMTraceLog -Message "Supporting path created: $($lRepoParentPath)" -Type $TypeWarn }
            } Catch {
                if ( $DebugMode ) { CMTraceLog -Message "Supporting path creation Failed: $($lRepoParentPath)" -Type $TypeError }
                CMTraceLog -Message "[init_repository] Done" -Type $TypeNorm
                return $retRepoCreated
            } # Catch
        } # if ( !(Test-Path $lRepoPathSplit) ) 

        #--------------------------------------------------------------------------------
        # now add the Repo folder if it doesn't exist

        if ( !(Test-Path $pRepoFolder) ) {
            CMTraceLog -Message '... creating Repository Folder' -Type $TypeNorm
            New-Item -Path $pRepoFolder -ItemType directory
        } # if ( !(Test-Path $RepoShareMain) )

        $retRepoCreated = $true

        #--------------------------------------------------------------------------------
        # if needed, check on repository to initialize (CMSL repositories have a .Repository folder)

        if ( $pInitRepository -and !(test-path "$pRepoFolder\.Repository")) {
            Set-Location $pRepoFolder
            $initOut = (Initialize-Repository) 6>&1
            CMTraceLog -Message  "... Repository Initialization done: $($Initout)"  -Type $TypeNorm 

            CMTraceLog -Message  '... configuring this repository for HP Image Assistant' -Type $TypeNorm
            Set-RepositoryConfiguration -setting OfflineCacheMode -cachevalue Enable 6>&1   # configuring the repo for HP IA's use

        } # if ( $pInitRepository -and !(test-path "$pRepoFOlder\.Repository"))

    } # else if ( (Test-Path $pRepoFolder) -and ($pInitRepository -eq $false) )

    Set-Location $pCurrentLoc

    CMTraceLog -Message "< init_repository" -Type $TypeNorm
    return $retRepoCreated

} # Function init_repository

#=====================================================================================
<#
    Function Sync_Clenaup_Repository
        This function will run a Sync and a Cleanup commands from HPCMSL

    expects parameter 
        - Repository folder to sync
#>
Function Sync_Clenaup_Repository {
    [CmdletBinding()]
	param( $pFolder )                                      

    $pCurrentLoc = Get-Location

    if ( Test-Path $pFolder ) {

        #--------------------------------------------------------------------------------
        # update repository softpaqs with sync command and then cleanup
        #--------------------------------------------------------------------------------

        Set-Location -Path $pFolder

        CMTraceLog -Message  '... invoking repository sync - please wait !!!' -Type $TypeNorm
        $lRes = (invoke-repositorysync 6>&1)
        CMTraceLog -Message "   ... $($lRes)" -Type $TypeWarn 

        $lListResult = $lRes -split { $_ -match 'File'}
        foreach ( $entry in $lListResult) {
            CMTraceLog -Message "   ... $($entry)" -Type $TypeWarn 
        }
        CMTraceLog -Message  '... invoking repository cleanup ' -Type $TypeNoNewline 
        $lRes = (invoke-RepositoryCleanup 6>&1)
        CMTraceLog -Message "... $($lRes)" -Type $TypeWarn

    }

    Set-Location $pCurrentLoc

} # Function Sync_Clenaup_Repository

Function Manage_Repository {
[CmdletBinding()]
	param( $pModelsList,                                             # array of row lines that are checked
            $pCheckedItemsList)                                      # array of rows selected
    
    $pCurrentLoc = Get-Location
    CMTraceLog -Message "> Manage_Repository " -Type $TypeNorm
    if ( $DebugMode ) { CMTraceLog -Message "... for OS version: $($OSVER)" -Type $TypeDebug }

    if ( $Script:SingleRepo ) {
        $lMainRepo =  $RepoShareSingle                               # 
        init_repository $lMainRepo $true                             # make sure Main repo folder exists, or create it - no init
    } else {
        $lMainRepo =  $RepoShareMain                                 # 
        init_repository $lMainRepo $false                            # make sure Main repo folder exists, do NOT make it a repository
    }
    #--------------------------------------------------------------------------------
    if ( $DebugMode ) { CMTraceLog -Message "... stepping through all selected models" -Type $TypeDebug }

    # go through every selected HP Model in the list

    for ( $i = 0; $i -lt $pModelsList.RowCount; $i++ ) {
        
        # if model entry is checked, we need to create a repository, but ONLY if $singleRepo = $false
        if ( $i -in $pCheckedItemsList ) {

            $lModelId = $pModelsList[1,$i].Value                      # column 1 has the Model/Prod ID
            $lModelName = $pModelsList[2,$i].Value                    # column 2 has the Model name

            if ( $Script:SingleRepo ) {
                $lTempRepoFolder = $lMainRepo
            } else {
                $lTempRepoFolder = "$($lMainRepo)\$($lModelName)"     # this is the repo folder for this model
                init_repository $lTempRepoFolder $true
            } # else if ( $Script:singleRepo -eq $false )

            # move to location of Repository to use CMSL repo commands
            set-location $lTempRepoFolder
            
            #--------------------------------------------------------------------------------
            # clean up filters for the current model in this loop
            #--------------------------------------------------------------------------------

            CMTraceLog -Message  "... removing filters for Sysid: $($lModelName)/$($lModelId)"  -Type $TypeNorm
            $lres = (Remove-RepositoryFilter -platform $lModelId -yes 6>&1)      
            if ( $debugMode ) { CMTraceLog -Message "... removed filter: $($lres)" -Type $TypeWarn }

            #--------------------------------------------------------------------------------
            # update filters - every category checked for the current model in this 'for loop'
            #--------------------------------------------------------------------------------

            if ( $DebugMode ) { CMTraceLog -Message "... adding category filters" -Type $TypeDebug }

            foreach ( $cat in $FilterCategories ) {

                if ( $datagridview.Rows[$i].Cells[$cat].Value ) {
                    CMTraceLog -Message  "... adding filter: -platform $($lModelId) -os win10 -osver $OSVER -category $($cat) -characteristic ssm" -Type $TypeNoNewline
                    $lRes = (Add-RepositoryFilter -platform $lModelId -os win10 -osver $OSVER -category $cat -characteristic ssm 6>&1)
                    CMTraceLog -Message $lRes -Type $TypeWarn 
                }
            } # foreach ( $cat in $FilterCategories )

            #--------------------------------------------------------------------------------
            # update repository path for this model in the grid (col 8 is links col)
            #--------------------------------------------------------------------------------
            $datagridview[8,$i].Value = $lTempRepoFolder
            
            #--------------------------------------------------------------------------------
            # now sync up and cleanup this repository - if common repo, leave this for later
            #--------------------------------------------------------------------------------
            if ( $Script:SingleRepo -eq $false ) {
                Sync_Clenaup_Repository $lTempRepoFolder
            }

            #--------------------------------------------------------------------------------
            # update SCCM Repository package, if user allows
            #--------------------------------------------------------------------------------
            if ( $Script:UpdateCMPackages ) {
                CM_RepoUpdate $lModelName $lModelId $lTempRepoFolder
            }
            
        } # if ( $i -in $pCheckedItemsList )

    } # for ( $i = 0; $i -lt $pModelsList.RowCount; $i++ )

    if ( $Script:SingleRepo ) {
        Sync_Clenaup_Repository $lMainRepo
    } # if ( $Script:SingleRepo )

    #--------------------------------------------------------------------------------
    Set-Location -Path $pCurrentLoc

    CMTraceLog -Message "< Manage_Repository" -Type $TypeNorm

} # Function Manage_Repository

#=====================================================================================
<#
    Function clear_datagrid
        clear all checkmarks and last path column '8', except for SysID and Model columns

#>
Function clear_datagrid {
    [CmdletBinding()]
	param( $pDataGrid )                             

    CMTraceLog -Message '> clear_datagrid' -Type $TypeNorm

    for ( $row = 0 ; $row -lt $pDataGrid.RowCount ; $row++ ) {
        for ( $col = 0 ; $col -lt $pDataGrid.ColumnCount ; $col++ ) {
            if ( $col -in @(0,3,4,5,6,7) ) {
                $pDataGrid[$col,$row].value = $false                       # clear checkmarks
            } else {
                if ( $pDataGrid.columns[$col].Name -match 'Repo' ) {
                    $pDataGrid[$col,$row].value = ''                       # clear path text field
                }
            }
        }
    } # for ( $row = 0 ; $row -lt $pDataGrid.RowCount ; $row++ ) 
    
    CMTraceLog -Message '< clear_datagrid' -Type $TypeNorm
} # Function clear_datagrid

#=====================================================================================
<#
    Function get_filters
        Retrieves category filters from the share for each selected model
        ... and populates the Grid appropriately

#>
Function get_filters {
    [CmdletBinding()]
	param( $pDataGridList )                             # array of row lines that are checked

    $pCurrentLoc = Get-Location

    CMTraceLog -Message '> get_filters' -Type $TypeNorm
    
    Set-Location "C:\" #-PassThru

    if ( $Script:SingleRepo ) {
        $lMainRepo =  $RepoShareSingle                               # make sure Main repo folder exists, or create it - no init
    } else {
        $lMainRepo =  $RepoShareMain                                 # check folder, and initialize for HPIA
    }
    clear_datagrid $pDataGridList

    #--------------------------------------------------------------------------------
    # find out if the share exists, if not, just return
    #--------------------------------------------------------------------------------
    if ( Test-Path $lMainRepo ) {
        CMTraceLog -Message '... Main Repo Host Folder exists - will check for selected Models' -Type $TypeNorm

        #--------------------------------------------------------------------------------
        if ( $Script:singleRepo ) {
            # see if the repository was configured for HPIA

            if ( !(Test-Path "$($lMainRepo)\.Repository") ) {
                CMTraceLog -Message "... Repository Folder not initialized" -Type $TypeNorm
                CMTraceLog -Message '[get_filters] Done' -Type $TypeNorm
                return
            } 
            set-location $lMainRepo            

            $lProdFilters = (get-repositoryinfo).Filters

            foreach ( $filterSetting in $lProdFilters ) {

                if ( $DebugMode ) { CMTraceLog -Message "... populating filter categories ''$($lModelName)''" -Type $TypeDebug }

                # check each row SysID against the Filter Platform ID
                for ( $i = 0; $i -lt $pDataGridList.RowCount; $i++ ) {

                    if ( $filterSetting.platform -eq $pDataGridList[1,$i].value) {
                        # we matched the row/SysId with the Filter Platform IF, so let's add each category in the filter
                        foreach ( $cat in  ($filterSetting.category.split(' ')) ) {
                            $pDataGridList.Rows[$i].Cells[$cat].Value = $true
                        }
                        $pDataGridList[0,$i].Value = $true
                        $pDataGridList[8,$i].Value = $lMainRepo
                    }

                } # for ( $i = 0; $i -lt $pDataGridList.RowCount; $i++ )
            } # foreach ( $platform in $lProdFilters )
        
        } else {

            #--------------------------------------------------------------------------------
            # now check for each product's repository folder
            # if the repo is created, then check the category filters
            #--------------------------------------------------------------------------------
            for ( $i = 0; $i -lt $pDataGridList.RowCount; $i++ ) {

                $lModelId = $pDataGridList[1,$i].Value                                                # column 1 has the Model/Prod ID
                $lModelName = $pDataGridList[2,$i].Value                                              # column 2 has the Model name

                $lTempRepoFolder = "$($lMainRepo)\$($lModelName)"                               # this is the repo folder for this model

                # move to location of Repository to use CMSL repo commands
                if ( Test-Path $lTempRepoFolder ) {
                    set-location $lTempRepoFolder

                    ###### filters sample obtained with get-repositoryinfo: 
                    # platform        : 8438
                    # operatingSystem : win10:2004 win10:2004
                    # category        : BIOS firmware
                    # releaseType     : *
                    # characteristic  : ssm
                    ###### 
                    $lProdFilters = (get-repositoryinfo).Filters

                    foreach ( $platform in $lProdFilters ) {

                        CMTraceLog -Message "... populating filter categories ''$($lModelName)''" -Type $TypeDebug
                        
                        foreach ( $cat in  ($lProdFilters.category.split(' ')) ) {
                            $pDataGridList.Rows[$i].Cells[$cat].Value = $true
                        }
                        #--------------------------------------------------------------------------------
                        # show repository path for this model (model is checked) (col 8 is links col)
                        #--------------------------------------------------------------------------------
                        $pDataGridList[0,$i].Value = $true
                        $pDataGridList[8,$i].Value = $lTempRepoFolder

                    } # foreach ( $platform in $lProdFilters )

                } # if ( Test-Path $lTempRepoFolder )
            } # for ( $i = 0; $i -lt $pModelsList.RowCount; $i++ ) 


        } # if ( $Script:singleRepo )

    } else {
        if ( $DebugMode ) { CMTraceLog -Message 'Main Repo Host Folder ''$($lMainRepo)'' does NOT exist' -Type $TypeDebug }
        #CMTraceLog -Message '... Main Repo Host Folder ''$($lMainRepo)'' does NOT exist' -Type $TypeNorm
    } # else if ( !(Test-Path $lMainRepo) )

    Set-Location -Path $pCurrentLoc

    CMTraceLog -Message '< get_filters]' -Type $TypeNorm
    
} # Function get_filters

#=====================================================================================
<#
    Function CreateForm
    This is the MAIN function with a Gui that sets things up for the user
#>
Function CreateForm {
    
    Add-Type -assembly System.Windows.Forms

    $LeftOffset = 20
    $TopOffset = 20
    $FieldHeight = 20
    $FormWidth = 800
    $FormHeight = 600
    if ( $DebugMode ) { Write-Host 'creating Form' }
    $CM_form = New-Object System.Windows.Forms.Form
    $CM_form.Text = "CM_HPIARepo_Downloader v$($ScriptVersion)"
    $CM_form.Width = $FormWidth
    $CM_form.height = $FormHeight
    $CM_form.Autosize = $true
    $CM_form.StartPosition = 'CenterScreen'

    #----------------------------------------------------------------------------------
    # Create Sync button
    #----------------------------------------------------------------------------------
    if ( $DebugMode ) { Write-Host 'creating Sync button' }
    $buttonSync = New-Object System.Windows.Forms.Button
    $buttonSync.Width = 60
    $buttonSync.Text = 'Sync'
    $buttonSync.Location = New-Object System.Drawing.Point(($LeftOffset+20),($TopOffset-1))

    $buttonSync.add_click( {

        # Modify INI file with newly selected OSVER

        if ( $Script:OSVER -ne $OSVERComboBox.Text ) {
            if ( $DebugMode ) { CMTraceLog -Message 'modifying INI file with selected OSVER' -Type $TypeNorm }
            $find = "^[\$]OSVER"
            $replace = "`$OSVER = ""$($OSVERComboBox.Text)"""  
            (Get-Content $IniFIleFullPath) | Foreach-Object {if ($_ -match $find) {$replace} else {$_}} | Set-Content $IniFIleFullPath
        } 

        $Script:OSVER = $OSVERComboBox.Text                            # get selected version
        if ( $Script:OSVER -in $Script:OSVALID ) {
            # selected rows are those that have a checkmark on column 0
            # get a list of all models selected (row numbers, starting with 0)
            # ... and add each entry to an array to be used by the sync function
            $lCheckedListArray = @()
            for ($i = 0; $i -lt $dataGridView.RowCount; $i++) {
                if ($dataGridView[0,$i].Value) {
                    $lCheckedListArray += $i
                } # if  
            } # for

            if ( $updateCMCheckbox.checked ) {
                if ( ($Script:CMConnected = Test_CMConnection) ) {
                    if ( $DebugMode ) { CMTraceLog -Message 'Script connected to CM' -Type $TypeDebug }
                }
            }
            Manage_Repository $dataGridView $lCheckedListArray

        } # if ( $Script:OSVER -in $Script:OSVALID )

    } ) # $buttonSync.add_click

    #$CM_form.Controls.AddRange(@($buttonSync, $ActionComboBox))
    $CM_form.Controls.AddRange(@($buttonSync))

    #----------------------------------------------------------------------------------
    # Create OS and OS Version display fields - info from .ini file
    #----------------------------------------------------------------------------------
    if ( $DebugMode ) { Write-Host 'creating OS Combo and Label' }
    $OSTextLabel = New-Object System.Windows.Forms.Label
    $OSTextLabel.Text = "Win 10 Version:"
    $OSTextLabel.location = New-Object System.Drawing.Point(($LeftOffset+90),($TopOffset+4))    # (from left, from top)
    $OSTextLabel.Size = New-Object System.Drawing.Size(90,25)                               # (width, height)
    #$OSTextField = New-Object System.Windows.Forms.TextBox
    $OSVERComboBox = New-Object System.Windows.Forms.ComboBox
    $OSVERComboBox.Size = New-Object System.Drawing.Size(60,$FieldHeight)                  # (width, height)
    $OSVERComboBox.Location  = New-Object System.Drawing.Point(($LeftOffset+180), ($TopOffset))
    $OSVERComboBox.DropDownStyle = "DropDownList"
    $OSVERComboBox.Name = "OS_Selection"
    $OSVERComboBox.add_MouseHover($ShowHelp)
    
    # populate menu list from INI file
    Foreach ($MenuItem in $OSVALID) {
        [void]$OSVERComboBox.Items.Add($MenuItem);
    }  
    $OSVERComboBox.SelectedItem = $OSVER 

    $CM_form.Controls.AddRange(@($OSTextLabel,$OSVERComboBox))

    #----------------------------------------------------------------------------------
    # Create 'Debug Mode' - checkmark
    #----------------------------------------------------------------------------------
    $DebugCheckBox = New-Object System.Windows.Forms.CheckBox
    $DebugCheckBox.Text = 'Debug Mode'
    $DebugCheckBox.UseVisualStyleBackColor = $True
    $DebugCheckBox.location = New-Object System.Drawing.Point(($LeftOffset+260),$TopOffset)   # (from left, from top)
    $DebugCheckBox.checked = $Script:DebugMode
    $DebugCheckBox.add_click( {
            if ( $DebugCheckBox.checked ) {
                $Script:DebugMode = $true
            } else {
                $Script:DebugMode = $false
            }
        }
    ) # $DebugCheckBox.add_click

    $CM_form.Controls.Add($DebugCheckBox)                    # removed CM Connect Button

    #----------------------------------------------------------------------------------
    # add share info field
    #----------------------------------------------------------------------------------
    if ( $DebugMode ) { Write-Host 'creating Share field' }
    $SharePathLabel = New-Object System.Windows.Forms.Label
    $SharePathLabel.Text = "Share"
    $SharePathLabel.location = New-Object System.Drawing.Point(($LeftOffset-10),($TopOffset-4)) # (from left, from top)
    $SharePathLabel.Size = New-Object System.Drawing.Size(50,16)                            # (width, height)
    $SharePathLabel.TextAlign = "MiddleRight"
    $SharePathTextField = New-Object System.Windows.Forms.TextBox
    $SharePathTextField.Text = "$RepoShareMain"
    $SharePathTextField.Multiline = $false 
    $SharePathTextField.location = New-Object System.Drawing.Point(($LeftOffset+50),($TopOffset-4)) # (from left, from top)
    $SharePathTextField.Size = New-Object System.Drawing.Size(290,$FieldHeight)             # (width, height)
    $SharePathTextField.ReadOnly = $true
    $SharePathTextField.Name = "Share_Path"

    $SharePathLabelSingle = New-Object System.Windows.Forms.Label
    $SharePathLabelSingle.Text = "Common"
    $SharePathLabelSingle.location = New-Object System.Drawing.Point(($LeftOffset-10),($TopOffset+15)) # (from left, from top)
    $SharePathLabelSingle.Size = New-Object System.Drawing.Size(50,20)                            # (width, height)
    $SharePathLabelSingle.TextAlign = "MiddleRight"
    $SharePathSingleTextField = New-Object System.Windows.Forms.TextBox
    $SharePathSingleTextField.Text = "$RepoShareSingle"
    $SharePathSingleTextField.Multiline = $false 
    $SharePathSingleTextField.location = New-Object System.Drawing.Point(($LeftOffset+50),($TopOffset+15)) # (from left, from top)
    $SharePathSingleTextField.Size = New-Object System.Drawing.Size(290,$FieldHeight)             # (width, height)
    $SharePathSingleTextField.ReadOnly = $true
    $SharePathSingleTextField.Name = "Single_Share_Path"
    
    $CMGroupBox = New-Object System.Windows.Forms.GroupBox
    $CMGroupBox.location = New-Object System.Drawing.Point(($LeftOffset+370),($TopOffset))     # (from left, from top)
    $CMGroupBox.Size = New-Object System.Drawing.Size(370,65)                              # (width, height)
    $CMGroupBox.text = "Share Paths - from ($($IniFile)):"

    $CMGroupBox.Controls.AddRange(@($SharePathLabel, $SharePathTextField, $SharePathLabelSingle, $SharePathSingleTextField))

    $CM_form.Controls.AddRange(@($CMGroupBox))

    #----------------------------------------------------------------------------------
    # Create Single Repository checkbox
    #----------------------------------------------------------------------------------
    if ( $DebugMode ) { Write-Host 'creating Single Repo Checkbox' }
    $singleRepoheckbox = New-Object System.Windows.Forms.CheckBox
    $singleRepoheckbox.Text = 'Use Single Repository'
    $singleRepoheckbox.Autosize = $true
    $singleRepoheckbox.Location = New-Object System.Drawing.Point(($LeftOffset+20),($TopOffset+30))

    $lBackgroundColor = 'LightSteelBlue'

    # populate CM Udate checkbox from .INI variable setting
    $find = "^[\$]SingleRepo"
    (Get-Content $IniFIleFullPath) | Foreach-Object { 
            if ($_ -match $find) { 
                if ( $_ -match '\$true' ) { 
                    $singleRepoheckbox.Checked = $true                          # set the visual default from the INI setting
                    $SharePathSingleTextField.BackColor = $lBackgroundColor
                } else { 
                    $singleRepoheckbox.Checked = $false 
                    $SharePathTextField.BackColor = $lBackgroundColor
                }
            } # if ($_ -match $find)
        } # Foreach-Object

    $Script:SingleRepo  = $singleRepoheckbox.Checked                       

    $singleRepoheckbox_Click = {
        $find = "^[\$]SingleRepo"
        if ( $singleRepoheckbox.checked ) {
            $Script:SingleRepo = $true
            $SharePathSingleTextField.BackColor = $lBackgroundColor
            $SharePathTextField.BackColor = ""
        } else {
            $Script:SingleRepo = $false
            $SharePathSingleTextField.BackColor = ""
            $SharePathTextField.BackColor = $lBackgroundColor        
        }
        $replace = "`$SingleRepo = `$$Script:SingleRepo"                   # set up the replacing string to either $false or $true from ini file
        CMTraceLog -Message "updating INI setting to ''$($replace)''" -Type $TypeNorm
        (Get-Content $IniFIleFullPath) | Foreach-Object {if ($_ -match $find) {$replace} else {$_}} | Set-Content $IniFIleFullPath

        get_filters $dataGridView                                          # re-populate categories for available systems
        
    } # $updateCMCheckbox_Click = 

    $singleRepoheckbox.add_Click($singleRepoheckbox_Click)

    $CM_form.Controls.Add($singleRepoheckbox)

    #----------------------------------------------------------------------------------
    # Create CM Repository Packages Update button
    #----------------------------------------------------------------------------------
    if ( $DebugMode ) { Write-Host 'creating Repo Checkbox' }
    $updateCMCheckbox = New-Object System.Windows.Forms.CheckBox
    $updateCMCheckbox.Text = 'Update SCCM Repo Packages'
    $updateCMCheckbox.Autosize = $true
    $updateCMCheckbox.Location = New-Object System.Drawing.Point(($LeftOffset+190),($TopOffset+30))

    # populate CM Udate checkbox from .INI variable setting - $UpdateCMPackages
    $find = "^[\$]UpdateCMPackages"
    (Get-Content $IniFIleFullPath) | Foreach-Object { 
        if ($_ -match $find) { 
            if ( $_ -match '\$true' ) { 
                $updateCMCheckbox.Checked = $true 
            } else { 
                $updateCMCheckbox.Checked = $false 
            }
                        } 
        } # Foreach-Object

    $Script:UpdateCMPackages = $updateCMCheckbox.Checked

    $updateCMCheckbox_Click = {
        $find = "^[\$]UpdateCMPackages"
        if ( $updateCMCheckbox.checked ) {
            $Script:UpdateCMPackages = $true
        } else {
            $Script:UpdateCMPackages = $false
        }
        $replace = "`$UpdateCMPackages = `$$Script:UpdateCMPackages"                   # set up the replacing string to either $false or $true from ini file
        CMTraceLog -Message "updating INI setting to ''$($replace)''" -Type $TypeNorm
        (Get-Content $IniFIleFullPath) | Foreach-Object {if ($_ -match $find) {$replace} else {$_}} | Set-Content $IniFIleFullPath

    } # $updateCMCheckbox_Click = 

    $updateCMCheckbox.add_Click($updateCMCheckbox_Click)

    $CM_form.Controls.Add($updateCMCheckbox)

    #----------------------------------------------------------------------------------
    # Create Models list Checked Grid box - add 1st checkbox column
    # The ListView control allows columns to be used as fields in a row
    #----------------------------------------------------------------------------------
    if ( $DebugMode ) { Write-Host 'creating DataGridView' }
    $ListViewWidth = ($FormWidth-80)
    $ListViewHeight = 200
    $dataGridView = New-Object System.Windows.Forms.DataGridView
    $dataGridView.location = New-Object System.Drawing.Point(($LeftOffset-10),($TopOffset))
    $dataGridView.height = $ListViewHeight
    $dataGridView.width = $ListViewWidth
    $dataGridView.ColumnHeadersVisible = $true                   # the column names becomes row 0 in the datagrid view
    $dataGridView.RowHeadersVisible = $false
    $dataGridView.SelectionMode = 'CellSelect'
    $dataGridView.AllowUserToAddRows = $False                    # Prevents the display of empty last row
    if ( $DebugMode ) {  Write-Host 'creating col 0 checkbox' }
    # add column 0 (0 is 1st column)
    $CheckBoxColumn = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $CheckBoxColumn.width = 28

    [void]$DataGridView.Columns.Add($CheckBoxColumn) 

    #----------------------------------------------------------------------------------
    # Add a CheckBox on header (to 1st col)
    # default the all checkboxes selected/checked
    #----------------------------------------------------------------------------------
    if ( $DebugMode ) { Write-Host 'creating Checkbox col 0 header' }
    $CheckAll=New-Object System.Windows.Forms.CheckBox
    $CheckAll.AutoSize=$true
    $CheckAll.Left=9
    $CheckAll.Top=6
    $CheckAll.Checked = $false

    $CheckAll_Click={

        $state = $CheckAll.Checked
        for ($i = 0; $i -lt $dataGridView.RowCount; $i++) {
            $dataGridView[0,$i].Value = $state  
            $dataGridView.Rows[$i].Cells['Driver'].Value = $state

            if ( $state -eq $false ) {
                foreach ( $cat in $FilterCategories ) {                                   
                    $datagridview.Rows[$i].Cells[$cat].Value = $false                # ... reset categories as well
                }
                get_filters $dataGridView
            } # if ( $state -eq $false )
        }
    } # $CheckAll_Click={

    $CheckAll.add_Click($CheckAll_Click)

    $dataGridView.Controls.Add($CheckAll)
    
    #----------------------------------------------------------------------------------
    # add columns 1, 2 (0 is 1st column)
    #----------------------------------------------------------------------------------
    if ( $DebugMode ) { Write-Host 'adding SysId, Model columns' }
    $dataGridView.ColumnCount = 3                                # 1st column is checkbox column

    $dataGridView.Columns[1].Name = 'SysId'
    $dataGridView.Columns[1].Width = 40
    $dataGridView.Columns[1].DefaultCellStyle.Alignment = "MiddleCenter"

    $dataGridView.Columns[2].Name = 'Model'
    $dataGridView.Columns[2].Width = 210

    #----------------------------------------------------------------------------------
    # add an 'All' Categories column
    # column 3 (0 is 1st column)
    #----------------------------------------------------------------------------------
    if ( $DebugMode ) { Write-Host 'creating All Checkbox column' }
    $CheckBoxesAll = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $CheckBoxesAll.Name = 'All'
    $CheckBoxesAll.width = 28
   
    # $CheckBoxesAll.state = Displayed, Resizable, ResizableSet, Selected, Visible

    #################################################################
    # any click on a checkbox in the column has to also make sure the
    # row is selected
    $CheckBoxesAll_Click = {
        $row = $this.currentRow.index  
        $colClicked = $this.currentCell.ColumnIndex                                       # find out what column was clicked
        $prevState = $dataGridView.rows[$row].Cells[$colClicked].EditedFormattedValue     # value BEFORE click action $true/$false
        $newState = !($prevState)                                                         # value AFTER click action $true/$false

        switch ( $colClicked ) {
            0 { 
                if ( $newState ) {
                    $datagridview.Rows[$row].Cells['Driver'].Value = $newState
                } else {
                    $datagridview.Rows[$row].Cells['All'].Value = $false
                    foreach ( $cat in $FilterCategories ) {                                   
                        $datagridview.Rows[$row].Cells[$cat].Value = $false
                    }
                } # else if ( $newState ) 
            } # 0
            3 {                                                                           # user clicked on 'All' category column
                $datagridview.Rows[$row].Cells[0].Value = $newState                       # ... reset row checkbox as appropriate
                foreach ( $cat in $FilterCategories ) {                                   
                    $datagridview.Rows[$row].Cells[$cat].Value = $newState                # ... reset categories as well
                }
            } # 3
            default {
                foreach ( $cat in $FilterCategories ) {
                    $currColumn = $datagridview.Rows[$row].Cells[$cat].ColumnIndex
                    if ( $colClicked -eq $currColumn ) {
                        continue                                                          # this column already handled by vars above, need to check other categories
                    } else {
                        if ( $datagridview.Rows[$row].Cells[$cat].Value ) {
                            $newState = $true
                        }
                    }
                } # foreach ( $cat in $FilterCategories )
 
                $datagridview.Rows[$row].Cells[0].Value = $newState
            } # default
        } # switch ( $colClicked )
  
    } # $CheckBoxesAll_CellClick

    $dataGridView.Add_Click($CheckBoxesAll_Click)
    #################################################################
   
    [void]$DataGridView.Columns.Add($CheckBoxesAll)

    #----------------------------------------------------------------------------------
    # Add checkbox columns for every category filter
    # column 4 on (0 is 1st column)
    #----------------------------------------------------------------------------------
    if ( $DebugMode ) { Write-Host 'creating category columns' }
    foreach ( $id in $FilterCategories ) {
        $temp = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
        $temp.name = $id
        $temp.width = 50
        [void]$DataGridView.Columns.Add($temp) 
    }

    # populate with all the HP Models listed in the ini file
    $HPModelsTable | ForEach-Object {
                        # populate 1st 3 columns: checkmark, ProdId, Model Name
                        $row = @( $true, $_.ProdCode, $_.Model)         
                        [void]$dataGridView.Rows.Add($row)
                } # ForEach-Object
    
    #----------------------------------------------------------------------------------
    # add a repository path as last column
    #----------------------------------------------------------------------------------
    if ( $DebugMode ) { Write-Host 'creating Repo links column' }
    $LinkColumn = New-Object System.Windows.Forms.DataGridViewColumn
    $LinkColumn.Name = 'Repository'
    $LinkColumn.ReadOnly = $true

    [void]$dataGridView.Columns.Add($LinkColumn,"Repository Path")

    $dataGridView.Columns[8].Width = 200

    #----------------------------------------------------------------------------------
    # next 2 lines clear any selection from the initial data view
    #----------------------------------------------------------------------------------
    $dataGridView.CurrentCell = $dataGridView[1,1]
    $dataGridView.ClearSelection()
    
    ###################################################################################
    # Set initial state for each row      
    
    # uncheck all rows' check column
    for ($i = 0; $i -lt $dataGridView.RowCount; $i++) {
        $dataGridView[0,$i].Value = $false
    }
    ###################################################################################

    #----------------------------------------------------------------------------------
    # Add a grouping box around the Models Grid with its name
    #----------------------------------------------------------------------------------
    if ( $DebugMode ) { Write-Host 'creating GroupBox' }

    $CMModlesGroupBox = New-Object System.Windows.Forms.GroupBox
    $CMModlesGroupBox.location = New-Object System.Drawing.Point($LeftOffset,($TopOffset+60))     # (from left, from top)
    $CMModlesGroupBox.Size = New-Object System.Drawing.Size(($ListViewWidth+20),($ListViewHeight+30))       # (width, height)
    $CMModlesGroupBox.text = "HP Models / Repository Filters"

    $CMModlesGroupBox.Controls.AddRange(@($dataGridView))

    $CM_form.Controls.AddRange(@($CMModlesGroupBox))
    
    #----------------------------------------------------------------------------------
    # Create Output Text Box at the bottom of the dialog
    #----------------------------------------------------------------------------------
    if ( $DebugMode ) { Write-Host 'creating RichTextBox' }
    $Script:TextBox = New-Object System.Windows.Forms.RichTextBox
    $TextBox.Name = $Script:FormOutTextBox                                          # named so other functions can output to it
    $TextBox.Multiline = $true
    $TextBox.Autosize = $false
    $TextBox.ScrollBars = "Both"
    $TextBox.WordWrap = $false
    $TextBox.location = New-Object System.Drawing.Point($LeftOffset,($TopOffset+300))            # (from left, from top)
    $TextBox.Size = New-Object System.Drawing.Size(($FormWidth-60),230)             # (width, height)

    $CM_form.Controls.AddRange(@($TextBox))

    #----------------------------------------------------------------------------------
    # Add a TextBox wrap CheckBox
    #----------------------------------------------------------------------------------
    if ( $DebugMode ) { Write-Host 'creating textbox Word Wrap checkmark' }
    $CheckWordwrap = New-Object System.Windows.Forms.CheckBox
    $CheckWordwrap.Location = New-Object System.Drawing.Point($LeftOffset,($FormHeight-45))    # (from left, from top)
    $CheckWordwrap.Text = 'Wrap Text'
    $CheckWordwrap.AutoSize=$true
    $CheckWordwrap.Checked = $false

    $CheckWordwrap_Click={
        $state = $CheckWordwrap.Checked
        if ( $CheckWordwrap.Checked ) {
            $TextBox.WordWrap = $true
        } else {
            $TextBox.WordWrap = $false
        }
    } # $CheckWordwrap_Click={

    $CheckWordwrap.add_Click($CheckWordwrap_Click)

    $CM_form.Controls.Add($CheckWordwrap)
 
    #----------------------------------------------------------------------------------
    # Add a clear TextBox CheckBox
    #----------------------------------------------------------------------------------
    if ( $DebugMode ) { Write-Host 'creating a clear textbox checkmark' }
    $ClearTextBox = New-Object System.Windows.Forms.Button
    $ClearTextBox.Location = New-Object System.Drawing.Point(($LeftOffset+100),($FormHeight-47))    # (from left, from top)
    $ClearTextBox.Text = 'Clear TextBox'
    $ClearTextBox.AutoSize=$true

    $ClearTextBox_Click={
        $TextBox.Clear()
    } # $CheckWordwrap_Click={

    $ClearTextBox.add_Click($ClearTextBox_Click)

    $CM_form.Controls.Add($ClearTextBox)
 
    #----------------------------------------------------------------------------------
    # Create Done/Exit Button at the bottom of the dialog
    #----------------------------------------------------------------------------------
    if ( $DebugMode ) { Write-Host 'creating Done Button' }
    $buttonDone = New-Object System.Windows.Forms.Button
    $buttonDone.Text = 'Done'
    $buttonDone.Location = New-Object System.Drawing.Point(($FormWidth-120),($FormHeight-50))    # (from left, from top)

    $buttonDone.add_click( {
            $CM_form.Close()
            $CM_form.Dispose()
        }
    ) # $buttonDone.add_click
     
    $CM_form.Controls.AddRange(@($buttonDone))
    
    #----------------------------------------------------------------------------------
    # now, make sure we have the HP CMSL modules available to run in the script
    #----------------------------------------------------------------------------------
    Load_HPModule

    #----------------------------------------------------------------------------------
    # Finally, show the dialog on screen
    #----------------------------------------------------------------------------------
    if ( $DebugMode ) { Write-Host 'calling get_filters' }
    get_filters $dataGridView

    if ( $DebugMode ) { Write-Host 'calling ShowDialog' }
    $CM_form.ShowDialog() | Out-Null

} # Function CreateForm

# --------------------------------------------------------------------------
# Start of Script
# --------------------------------------------------------------------------

#CMTraceLog -Message "Starting Script: $scriptName, version $ScriptVersion" -Type $TypeNorm

# Create the GUI and take over all actions, like Report and Download

CreateForm
<#
#>
