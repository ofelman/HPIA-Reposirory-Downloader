# HPIA-Repository-Downloader
The script is designed to create and maintain HP Image Assistant offline repositories with a GUI interface
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
    Version 1.20
        Fixed single repository filter cleanup... was not removing all other platform filters previously
        Added function to show Softpaqs added (or not) after a Sync
        Added button to reread model filters from repositories and refresh the grid
    Version 1.25
        Code cleanup of Function sync_repositories - split into 2 functions Single repo, and multiple/individual repositories
        changed 'use single repository' checkbox to radio buttons on path fields (removed checkbox)
        Added 'Distribute SCCM Packages' ($DistributeCMPackages) variable use in INI file
            -- when selected, sends command to CM to Distribute packages, otherwise SCCM packages are created/updated only
    Version 1.30
        Added ability to sync specific softpaqs by name - listed in INI file
            -- added SqName entry to $HPModelsTable list to hold special softpaqs needed/model
    Version 1.31
        moved Debug Mode checkbox to bottom
        added HPIA folder view, and HPIA button to initiate a create/update package in CM
    Version 1.32
        Moved HPIA button and file path to SCCM group in UI
    Version 1.40
        increased windows size based on feedback
        added checkmark to keep existing category filters - useful when maintaining Softpaqs for more than a single OS Version
        added checks for, and report on, CMSL Repository Sync errors 
        added function to list current category filters
        added separate function to modify setting in INI.ps1 file
        added buttons to increase and decrease output textbox text size
    Version 1.41
        added IP lookup for internet connetion local and remote - useful for debugging... post to HPA's log file
