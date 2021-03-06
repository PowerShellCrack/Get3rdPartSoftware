<#
    .INFO
        Script:         Get-3rdPartySoftware.ps1    
        Author:         Richard Tracy
        Email:          richard.tracy@hotmail.com
        Twitter:        @rick2_1979
        Website:        www.powershellcrack.com
        Last Update:    05/12/2020
        Version:        2.1.5
        Thanks to:      michaelspice

    .DISCLOSURE
        THE SCRIPT IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES 
        OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. BY USING OR DISTRIBUTING THIS SCRIPT, YOU AGREE THAT
        IN NO EVENT SHALL THE AUTHOR OR ANY AFFILATES BE HELD LIABLE FOR ANY CLAIM, ANY DAMAGES OR OTHER LIABILITY WHATSOEVER RESULTING
        FROM USING OR DISTRIBUTION OF THIS SCRIPT AND SOFTWARE, INCLUDING, WITHOUT LIMITATION, ANY SPECIAL, CONSEQUENTIAL, INCIDENTAL
        OR OTHER DIRECT OR INDIRECT DAMAGES. BACKUP UP ALL DATA BEFORE EXCUTING. 
    
    .SYNOPSIS
        Download 3rd party Software and updates

    .DESCRIPTION
        Parses third party updates sites for download links, then downloads them to their respective folder. 
        Builds an XML file with details of each software for processing later

    .PARAMETER DownloadPath
        Specified an alternate download path. Defaults to relative path of script under software folder

    .PARAMETER LogPath
        Specified an alternate log path. Defaults to relative path of script under log folder

    .EXAMPLE
        powershell.exe -file "Get-3rdPartySoftware.ps1"
        powershell.exe -file "Get-3rdPartySoftware.ps1" -DownloadPath D:\Repository\3rdPartySoftware\
        powershell.exe -file "Get-3rdPartySoftware.ps1" -DownloadPath D:\Repository\3rdPartySoftware\ -LogPath D:\Logs\

    .NOTES
        This script is a web crawler; it literally crawls the publishers website and looks for html tags to find hyperlinks.
        Then crawls those hyperlinks to grab versioning and eventually download the software. Each software has a custom crawler function, and is called at the very bottom of the script.  
        There is no API or JSON service it pulls from, besides firefox version control. 

    .LINK
        https://michaelspice.net/windows/windows-software

    
    .CHANGE LOG
        2.1.5 - May 12, 2020 - Added Cleanup switch to all functions
        2.1.4 - Oct 29, 2019 - Fixed content header function to use any webcontent; fixed firefox webrequest to use basic parsing. Added Firefox msi support
        2.1.3 - Jul 15, 2019 - Added parameter to script for task secheduler calls. Added Creation data
        2.1.1 - Jun 20, 2019 - Updated Firefox new URL; removed validatesets option for both to default; built function Get-WebRequestHeader   
        2.1.0 - Jun 18, 2019 - Added Adobe JDK and PowerBI update download   
        2.0.6 - Jun 13, 2019 - Added Adobe Acrobat DC Pro update download; set to clean log each time
        2.0.5 - May 15, 2019 - Added Get-ScriptPath function to support VScode and ISE; fixed Set-UserSettings  
        2.0.2 - May 14, 2019 - Added description to clixml; removed java 7 and changed Chrome version check uri
        2.0.1 = Apr 18, 2019 - Fixed chrome version check
        2.0.0 - Nov 02, 2018 - Added Download function and standardized all scripts; build clixml
        1.5.5 - Nov 01, 2017 - Added Github download
        1.5.0 - Sep 12, 2017 - Functionalized all 3rd party software crawlers
        1.1.1 - Mar 01, 2016 - added download for Firefox, 7Zip and VLC
        1.0.0 - Feb 11, 2016 - initial 
#> 
##*===========================================================================
##* PARAMS
##*===========================================================================
param(
    [Parameter(Mandatory=$false)]
    $DownloadPath,

    [Parameter(Mandatory=$false)]
    $LogPath,

    [Parameter(Mandatory=$false)]
    [boolean]$OverwriteFiles = $false,

    [Parameter(Mandatory=$false)]
    [boolean]$CleanupFiles = $false
)


#==================================================
# FUNCTIONS
#==================================================
#region FUNCTION: Check if running in ISE
Function Test-IsISE {
    # try...catch accounts for:
    # Set-StrictMode -Version latest
    try {
        return ($null -ne $psISE);
    }
    catch {
        return $false;
    }
}
#endregion
#region FUNCTION: Check if running in Visual Studio Code
Function Test-VSCode{
    if($env:TERM_PROGRAM -eq 'vscode') {
        return $true;
    }
    Else{
        return $false;
    }
}
#endregion

#region FUNCTION: Find script path for either ISE or console
Function Get-ScriptPath {
    <#
        .SYNOPSIS
            Finds the current script path even in ISE
    #>
    param([switch]$Parent)
    if ($PSScriptRoot -eq "")
    {
        if (Test-IsISE)
        {
            If($Parent){Split-Path $psISE.CurrentFile.FullPath -Parent}Else{$psISE.CurrentFile.FullPath}
        }
        elseif(Test-VSCode){
            ((Get-ChildItem).Directory | select -Unique).FullName
        }
        else
        {
            $context = $psEditor.GetEditorContext()
            $context.CurrentFile.Path
        }
    }
    else
    {
        If($Parent){Split-Path $PSCommandPath -Parent}Else{$PSCommandPath}
    }
}
#endregion

Function Format-DatePrefix {
    [string]$LogTime = (Get-Date -Format 'HH:mm:ss.fff').ToString()
	[string]$LogDate = (Get-Date -Format 'MM-dd-yyyy').ToString()
    return ($LogDate + " " + $LogTime)
}

Function Write-LogEntry {
    param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        [Parameter(Mandatory=$false,Position=2)]
		[string]$Source = '',
        [parameter(Mandatory=$false)]
        [ValidateSet(0,1,2,3,4)]
        [int16]$Severity,

        [parameter(Mandatory=$false, HelpMessage="Name of the log file that the entry will written to")]
        [ValidateNotNullOrEmpty()]
        [string]$OutputLogFile = $Global:LogFilePath,

        [parameter(Mandatory=$false)]
        [switch]$Outhost
    )
    Begin{
        [string]$LogTime = (Get-Date -Format 'HH:mm:ss.fff').ToString()
        [string]$LogDate = (Get-Date -Format 'MM-dd-yyyy').ToString()
        [int32]$script:LogTimeZoneBias = [timezone]::CurrentTimeZone.GetUtcOffset([datetime]::Now).TotalMinutes
        [string]$LogTimePlusBias = $LogTime + $script:LogTimeZoneBias
        
    }
    Process{
        # Get the file name of the source script
        Try {
            If ($script:MyInvocation.Value.ScriptName) {
                [string]$ScriptSource = Split-Path -Path $script:MyInvocation.Value.ScriptName -Leaf -ErrorAction 'Stop'
            }
            Else {
                [string]$ScriptSource = Split-Path -Path $script:MyInvocation.MyCommand.Definition -Leaf -ErrorAction 'Stop'
            }
        }
        Catch {
            $ScriptSource = ''
        }
        
        
        If(!$Severity){$Severity = 1}
        $LogFormat = "<![LOG[$Message]LOG]!>" + "<time=`"$LogTimePlusBias`" " + "date=`"$LogDate`" " + "component=`"$ScriptSource`" " + "context=`"$([Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " + "type=`"$Severity`" " + "thread=`"$PID`" " + "file=`"$ScriptSource`">"
        
        # Add value to log file
        try {
            Out-File -InputObject $LogFormat -Append -NoClobber -Encoding Default -FilePath $OutputLogFile -ErrorAction Stop
        }
        catch {
            Write-Host ("[{0}] [{1}] :: Unable to append log entry to [{1}], error: {2}" -f $LogTimePlusBias,$ScriptSource,$OutputLogFile,$_.Exception.Message) -ForegroundColor Red
        }
    }
    End{
        If($Outhost -or $Global:OutTohost){
            If($Source){
                $OutputMsg = ("[{0}] [{1}] :: {2}" -f $LogTimePlusBias,$Source,$Message)
            }
            Else{
                $OutputMsg = ("[{0}] [{1}] :: {2}" -f $LogTimePlusBias,$ScriptSource,$Message)
            }

            Switch($Severity){
                0       {Write-Host $OutputMsg -ForegroundColor Green}
                1       {Write-Host $OutputMsg -ForegroundColor Gray}
                2       {Write-Warning $OutputMsg}
                3       {Write-Host $OutputMsg -ForegroundColor Red}
                4       {If($Global:Verbose){Write-Verbose $OutputMsg}}
                default {Write-Host $OutputMsg}
            }
        }
    }
}

Function Show-ProgressStatus {
    <#
    .SYNOPSIS
        Shows task sequence secondary progress of a specific step
    
    .DESCRIPTION
        Adds a second progress bar to the existing Task Sequence Progress UI.
        This progress bar can be updated to allow for a real-time progress of
        a specific task sequence sub-step.
        The Step and Max Step parameters are calculated when passed. This allows
        you to have a "max steps" of 400, and update the step parameter. 100%
        would be achieved when step is 400 and max step is 400. The percentages
        are calculated behind the scenes by the Com Object.
    
    .PARAMETER Message
        The message to display the progress
    .PARAMETER Step
        Integer indicating current step
    .PARAMETER MaxStep
        Integer indicating 100%. A number other than 100 can be used.
    .INPUTS
         - Message: String
         - Step: Long
         - MaxStep: Long
    .OUTPUTS
        None
    .EXAMPLE
        Set's "Custom Step 1" at 30 percent complete
        Show-ProgressStatus -Message "Running Custom Step 1" -Step 100 -MaxStep 300
    
    .EXAMPLE
        Set's "Custom Step 1" at 50 percent complete
        Show-ProgressStatus -Message "Running Custom Step 1" -Step 150 -MaxStep 300
    .EXAMPLE
        Set's "Custom Step 1" at 100 percent complete
        Show-ProgressStatus -Message "Running Custom Step 1" -Step 300 -MaxStep 300
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string] $Message,
        [Parameter(Mandatory=$true)]
        [int]$Step,
        [Parameter(Mandatory=$true)]
        [int]$MaxStep,
        [string]$SubMessage,
        [int]$IncrementSteps,
        [switch]$Outhost
    )

    Begin{

        If($SubMessage){
            $StatusMessage = ("{0} [{1}]" -f $Message,$SubMessage)
        }
        Else{
            $StatusMessage = $Message
        }
    }
    Process
    {
        If($Script:tsenv){
            $Script:TSProgressUi.ShowActionProgress(`
                $Script:tsenv.Value("_SMSTSOrgName"),`
                $Script:tsenv.Value("_SMSTSPackageName"),`
                $Script:tsenv.Value("_SMSTSCustomProgressDialogMessage"),`
                $Script:tsenv.Value("_SMSTSCurrentActionName"),`
                [Convert]::ToUInt32($Script:tsenv.Value("_SMSTSNextInstructionPointer")),`
                [Convert]::ToUInt32($Script:tsenv.Value("_SMSTSInstructionTableSize")),`
                $StatusMessage,`
                $Step,`
                $Maxstep)
        }
        Else{ 
            Write-Progress -Activity "$Message ($Step of $Maxstep)" -Status $StatusMessage -PercentComplete (($Step / $Maxstep) * 100) -id 1
        }
    }
    End{

    }
}


Function Get-HrefMatches {
    param(
        ## The filename to parse
        [Parameter(Mandatory = $true)]
        [string] $content,
    
        ## The Regular Expression pattern with which to filter
        ## the returned URLs
        [string] $Pattern = "<\s*a\s*[^>]*?href\s*=\s*[`"']*([^`"'>]+)[^>]*?>"
    )

    $returnMatches = new-object System.Collections.ArrayList

    ## Match the regular expression against the content, and
    ## add all trimmed matches to our return list
    $resultingMatches = [Regex]::Matches($content, $Pattern, "IgnoreCase")
    foreach($match in $resultingMatches)
    {
        $cleanedMatch = $match.Groups[1].Value.Trim()
        [void] $returnMatches.Add($cleanedMatch)
    }

    $returnMatches
}

Function Get-Hyperlinks {
    param(
    [Parameter(Mandatory = $true)]
    [string] $content,
    [string] $Pattern = "<A[^>]*?HREF\s*=\s*""([^""]+)""[^>]*?>([\s\S]*?)<\/A>"
    )
    $resultingMatches = [Regex]::Matches($content, $Pattern, "IgnoreCase")
    
    $returnMatches = @()
    foreach($match in $resultingMatches){
        $LinkObjects = New-Object -TypeName PSObject
        $LinkObjects | Add-Member -Type NoteProperty `
            -Name Text -Value $match.Groups[2].Value.Trim()
        $LinkObjects | Add-Member -Type NoteProperty `
            -Name Href -Value $match.Groups[1].Value.Trim()
        
        $returnMatches += $LinkObjects
    }
    $returnMatches
}

Function Get-WebContentHeader{
    #https://stackoverflow.com/questions/41602754/get-website-metadata-such-as-title-description-from-given-url-using-powershell
    param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        #[Microsoft.PowerShell.Commands.HtmlWebResponseObject]$WebContent,
        $WebContent,

        [Parameter(Mandatory=$false)]
        [ValidateSet('Keywords','Description','Title')]
        [string]$Property
    )

    ## -------- PARSE TITLE, DESCRIPTION AND KEYWORDS ----------
    $resultTable = @{}
    # Get the title
    $resultTable.title = $WebContent.ParsedHtml.title
    # Get the HTML Tag
    $HtmlTag = $WebContent.ParsedHtml.childNodes | Where-Object {$_.nodename -eq 'HTML'} 
    # Get the HEAD Tag
    $HeadTag = $HtmlTag.childNodes | Where-Object {$_.nodename -eq 'HEAD'}
    # Get the Meta Tags
    $MetaTags = $HeadTag.childNodes| Where-Object {$_.nodename -eq 'META'}
    # You can view these using $metaTags | select outerhtml | fl 
    # Get the value on content from the meta tag having the attribute with the name keywords
    $resultTable.keywords = $metaTags  | Where-Object {$_.name -eq 'keywords'} | Select-Object -ExpandProperty content
    # Do the same for description
    $resultTable.description = $metaTags  | Where-Object {$_.name -eq 'description'} | Select-Object -ExpandProperty content
    # Return the table we have built as an object

    switch($Property){
        'Keywords'       {Return $resultTable.keywords}
        'Description'    {Return $resultTable.description}
        'Title'          {Return $resultTable.title}
        default          {Return $resultTable}
    }
}

Function Get-MSIInfo {
    param(
    [parameter(Mandatory=$true)]
    [IO.FileInfo]$Path,

    [parameter(Mandatory=$true)]
    [ValidateSet("ProductCode","ProductVersion","ProductName")]
    [string]$Property

    )
    try {
        $WindowsInstaller = New-Object -ComObject WindowsInstaller.Installer
        $MSIDatabase = $WindowsInstaller.GetType().InvokeMember("OpenDatabase","InvokeMethod",$Null,$WindowsInstaller,@($Path.FullName,0))
        $Query = "SELECT Value FROM Property WHERE Property = '$($Property)'"
        $View = $MSIDatabase.GetType().InvokeMember("OpenView","InvokeMethod",$null,$MSIDatabase,($Query))
        $View.GetType().InvokeMember("Execute", "InvokeMethod", $null, $View, $null)
        $Record = $View.GetType().InvokeMember("Fetch","InvokeMethod",$null,$View,$null)
        $Value = $Record.GetType().InvokeMember("StringData","GetProperty",$null,$Record,1)
        return $Value
        Remove-Variable $WindowsInstaller
    } 
    catch {
        Write-Output $_.Exception.Message
    }

}

Function Wait-FileUnlock {
    Param(
        [Parameter()]
        [IO.FileInfo]$File,
        [int]$SleepInterval=500
    )
    while(1){
        try{
           $fs=$file.Open('open','read', 'Read')
           $fs.Close()
            Write-Verbose "$file not open"
           return
           }
        catch{
           Start-Sleep -Milliseconds $SleepInterval
           Write-Verbose '-'
        }
	}
}

Function IsFileLocked {
    param(
        [Parameter(Mandatory=$true)]
        [string]$filePath
    )
    
    Rename-Item $filePath $filePath -ErrorVariable errs -ErrorAction SilentlyContinue
    return ($errs.Count -ne 0)
}

Function Get-FileSize{
    param(
        [Parameter(Mandatory=$true)]
        [string]$filePath
    )

    $result = Get-ChildItem $filePath | Measure-Object length -Sum | % {
        New-Object psobject -prop @{
            Size = $(
                switch ($_.sum) {
                    {$_ -gt 1tb} { '{0:N2}TB' -f ($_ / 1tb); break }
                    {$_ -gt 1gb} { '{0:N2}GB' -f ($_ / 1gb); break }
                    {$_ -gt 1mb} { '{0:N2}MB' -f ($_ / 1mb); break }
                    {$_ -gt 1kb} { '{0:N2}KB' -f ($_ / 1Kb); break }
                    default { '{0}B ' -f $_ } 
                }
            )
        }
    }

    $result | Select-Object -ExpandProperty Size
}
Function Initialize-FileDownload {
   param(
        [Parameter(Mandatory=$false)]
        [Alias("Title")]
        [string]$Name,
        
        [Parameter(Mandatory=$true,Position=1)]
        [string]$Url,
        
        [Parameter(Mandatory=$true,Position=2)]
        [Alias("TargetDest")]
        [string]$TargetFile
    )
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name

        ## Check running account
        [Security.Principal.WindowsIdentity]$CurrentProcessToken = [Security.Principal.WindowsIdentity]::GetCurrent()
        [Security.Principal.SecurityIdentifier]$CurrentProcessSID = $CurrentProcessToken.User
        [boolean]$IsLocalSystemAccount = $CurrentProcessSID.IsWellKnown([Security.Principal.WellKnownSidType]'LocalSystemSid')
        [boolean]$IsLocalServiceAccount = $CurrentProcessSID.IsWellKnown([Security.Principal.WellKnownSidType]'LocalServiceSid')
        [boolean]$IsNetworkServiceAccount = $CurrentProcessSID.IsWellKnown([Security.Principal.WellKnownSidType]'NetworkServiceSid')
        [boolean]$IsServiceAccount = [boolean]($CurrentProcessToken.Groups -contains [Security.Principal.SecurityIdentifier]'S-1-5-6')
        [boolean]$IsProcessUserInteractive = [Environment]::UserInteractive
    }
    Process
    {
        $ChildURLPath = $($url.split('/') | Select-Object -Last 1)

        $uri = New-Object "System.Uri" "$url"
        $request = [System.Net.HttpWebRequest]::Create($uri)
        $request.set_Timeout(15000) #15 second timeout
        $response = $request.GetResponse()
        $totalLength = [System.Math]::Floor($response.get_ContentLength()/1024)
        $responseStream = $response.GetResponseStream()
        $targetStream = New-Object -TypeName System.IO.FileStream -ArgumentList $targetFile, Create

        $buffer = new-object byte[] 10KB
        $count = $responseStream.Read($buffer,0,$buffer.length)
        $downloadedBytes = $count
   
        If($Name){$Label = $Name}Else{$Label = $ChildURLPath}

        Write-LogEntry ("Initializing File Download from URL: {0}" -f $Url) -Source ${CmdletName} -Severity 1

        while ($count -gt 0)
        {
            $targetStream.Write($buffer, 0, $count)
            $count = $responseStream.Read($buffer,0,$buffer.length)
            $downloadedBytes = $downloadedBytes + $count

            # display progress
            #  Check if script is running with no user session or is not interactive
            If ( ($IsProcessUserInteractive -eq $false) -or $IsLocalSystemAccount -or $IsLocalServiceAccount -or $IsNetworkServiceAccount -or $IsServiceAccount) {
                # display nothing
                write-host "." -NoNewline
            }
            Else{
                Show-ProgressStatus -Message ("Downloading: {0} ($([System.Math]::Floor($downloadedBytes/1024))K of $($totalLength)K): " -f $Label) -Step ([System.Math]::Floor($downloadedBytes/1024)) -MaxStep $totalLength
            }
        }

        Start-Sleep 3

        $targetStream.Flush()
        $targetStream.Close()
        $targetStream.Dispose()
        $responseStream.Dispose()
   }
   End{
        #Write-Progress -activity "Finished downloading file '$($url.split('/') | Select-Object -Last 1)'"
        If($Name){$Label = $Name}Else{$Label = $ChildURLPath}
        Show-ProgressStatus -Message ("Finished downloading file: {0}" -f $Label) -Step $totalLength -MaxStep $totalLength

        #change meta in file from internet to allow to run on system
        If(Test-Path $TargetFile){Unblock-File $TargetFile -ErrorAction SilentlyContinue | Out-Null}
   }
   
}

Function Get-FileProperties{
    Param(
        [io.fileinfo]$FilePath
        
     )
    $objFileProps = Get-item $filepath | Get-ItemProperty | Select-Object *
 
    #Get required Comments extended attribute
    $objShell = New-object -ComObject shell.Application
    $objShellFolder = $objShell.NameSpace((get-item $filepath).Directory.FullName)
    $objShellFile = $objShellFolder.ParseName((get-item $filepath).Name)
 
    $strComments = $objShellfolder.GetDetailsOf($objshellfile,24)
    $Version = [version]($strComments | Select-string -allmatches '(\d{1,4}\.){3}(\d{1,4})').matches.Value
    $objShellFile = $null
    $objShellFolder = $null
    $objShell = $null

    Add-Member -InputObject $objFileProps -MemberType NoteProperty -Name Version -Value $Version
    Return $objFileProps
}

Function Get-FtpDir{
    param(
        [Parameter(Mandatory=$true)]
        [string]$url,

        [System.Management.Automation.PSCredential]$credentials
    )
    $request = [Net.WebRequest]::Create($url)
    $request.Method = [System.Net.WebRequestMethods+FTP]::ListDirectory
    
    if ($credentials) { $request.Credentials = $credentials }
    
    $response = $request.GetResponse()
    $reader = New-Object IO.StreamReader $response.GetResponseStream() 
	$reader.ReadToEnd()
	$reader.Close()
	$response.Close()
}

##*===========================================================================
##* VARIABLES
##*===========================================================================
# Use function to get paths because Powershell ISE and other editors have differnt results
$scriptPath = Get-ScriptPath
[string]$scriptDirectory = Split-Path $scriptPath -Parent
[string]$scriptName = Split-Path $scriptPath -Leaf
[string]$scriptBaseName = [System.IO.Path]::GetFileNameWithoutExtension($scriptName)

$Global:Verbose = $false
If($PSBoundParameters.ContainsKey('Debug') -or $PSBoundParameters.ContainsKey('Verbose')){
    $Global:Verbose = $PsBoundParameters.Get_Item('Verbose')
    $VerbosePreference = 'Continue'
    Write-Verbose ("[{0}] [{1}] :: VERBOSE IS ENABLED." -f (Format-DatePrefix),$scriptName)
}
Else{
    $VerbosePreference = 'SilentlyContinue'
}

#Create log paths
If($LogPath){
    $RelativeLogPath = $LogPath
}
Else{
    $RelativeLogPath = Join-Path -Path $scriptDirectory -ChildPath 'Logs'
}
New-Item $RelativeLogPath -type directory -ErrorAction SilentlyContinue | Out-Null
#build log name
[string]$FileName = $scriptBaseName + '-' + (get-date -Format MM-dd-yyyy-hh-mm-ss) + '.log'
#build global log fullpath
$Global:LogFilePath = Join-Path $RelativeLogPath -ChildPath $FileName
#clean old log
if(Test-Path $Global:LogFilePath){remove-item -Path $Global:LogFilePath -ErrorAction SilentlyContinue | Out-Null}

Write-Host ("logging to file: {0}" -f $LogFilePath) -ForegroundColor Cyan

# BUILD FOLDER STRUCTURE
#=======================================================
#Create software path
If($DownloadPath){
    $SoftwarePath = $DownloadPath
}
Else{
    $SoftwarePath = Join-Path -Path $scriptDirectory -ChildPath 'Software'
    #ensure directory is created
    New-Item $SoftwarePath -type directory -ErrorAction SilentlyContinue | Out-Null

}

#check permissions on software path
Try{
    (Get-Acl $SoftwarePath).Access | Where-Object{$_.IdentityReference -match $User.SamAccountName} | Select-Object IdentityReference,FileSystemRights | Out-Null
    Write-LogEntry ("Downloading to [{0}]" -f $SoftwarePath) -Outhost     
}
Catch{
    Write-LogEntry ("Write permission to path [{0}] using credentials [{1}] are denied." -f $DownloadPath,$env:USERNAME) -Severity 3 -Outhost
    Exit -1
}

# JAVA 8 - DOWNLOAD
#==================================================
Function Get-Java8 {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,

        [parameter(Mandatory=$true)]
        [string]$FolderPath,

        [parameter(Mandatory=$false)]
        [ValidateSet('x86', 'x64')]
        [string]$Arch,

        [parameter(Mandatory=$false)]
        [switch]$Overwrite,

        [parameter(Mandatory=$false)]
        [switch]$Cleanup,

        [parameter(Mandatory=$false)]
        [switch]$ReturnDetails 
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        $Publisher = "Oracle"
        $Product = "Java 8"
        $Language = 'en'
        $ProductType = 'jre'

        [System.Uri]$SourceURL = "http://www.java.com/"
        [System.Uri]$DownloadURL = "http://www.java.com/$Language/download/manual.jsp"

        Try{
            ## -------- CRAWL DOWNLOAD SOURCE ----------
            #don't use basic parsing
            $DownloadContent = Invoke-WebRequest $DownloadURL -ErrorAction Stop
            Start-Sleep 3

            ## -------- PARSE VERSION ----------
            $javaTitle = $DownloadContent.AllElements | Where-Object{$_.outerHTML -like "*Version*"} | Where-Object{$_.innerHTML -like "*Update*"} | Select-Object -Last 1 -ExpandProperty outerText
            $parseVersion = $javaTitle.split("n ") | Select-Object -Last 3 #Split after n in version
            $JavaMajor = $parseVersion[0]
            $JavaMinor = $parseVersion[2]
            $Version = "1." + $JavaMajor + ".0." + $JavaMinor
            #$FileVersion = $parseVersion[0]+"u"+$parseVersion[2]

            Write-LogEntry ("{0}'s latest version is: [{1} Update {2}]" -f $Product,$JavaMajor,$JavaMinor) -Severity 1 -Source ${CmdletName} -Outhost
            $javaFileSuffix = ""

            ## -------- FIND DOWNLOAD LINKS ----------
            #get the appropiate url based on architecture
            switch($Arch){
                'x86' {$DownloadLinks = $DownloadContent.AllElements | Where-Object{$_.innerHTML -eq "Windows Offline"} | Select-Object -ExpandProperty href | Select-Object -First 1;
                    $javaFileSuffix = "-windows-i586.exe","";
                    $archLabel = 'x86',''}
                
                'x64' {$DownloadLinks = $DownloadContent.AllElements | Where-Object{$_.innerHTML -eq "Windows Offline (64-bit)"} | Select-Object -ExpandProperty href | Select-Object -First 1;
                    $javaFileSuffix = "-windows-x64.exe","";
                    $archLabel = 'x64',''}

                default {$DownloadLinks = $DownloadContent.AllElements | Where-Object{$_.innerHTML -like "Windows Offline*"} | Select-Object -ExpandProperty href | Select-Object -First 2;
                    $javaFileSuffix = "-windows-i586.exe","-windows-x64.exe";
                    $archLabel = 'x86','x64'}
            }

            ## -------- PARSE DESCRIPTION ----------
            #$Description = Get-WebContentHeader -WebContent $content -Property Description
            $AboutURL = ($DownloadContent.AllElements | Where-Object{$_.href -like "*/whatis*"}).href
            $content = Invoke-WebRequest ($SourceURL.OriginalString + $AboutURL) -ErrorAction Stop
            $Description = ($content.AllElements | Where-Object{$_.class -eq 'bodytext'} | Select-Object -First 2).innerText

            ## -------- BUILD FOLDERS ----------
            $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
            If( !(Test-Path $DestinationPath)){
                New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
            }

            #Remove all folders and files except the latest if they exist
            If($Cleanup){
                Get-ChildItem -Path $DestinationPath -Exclude sites.exception | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
                    Remove-Item $_.fullname -Recurse -Force | Out-Null
                    Write-LogEntry ("Removed File: [{0}]" -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
                }
            }

            #build Destination folder based on version
            New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null

            
            $i = 0
            Foreach ($link in $DownloadLinks){
    
                #build Download link from Root URL (if Needed)
                $DownloadLink = $link
                Write-LogEntry ("Validating Download Link: [{0}]" -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

                If($javaFileSuffix -eq 1){$i = 0}
                $Filename = $ProductType + "-" + $JavaMajor + "u" + "$JavaMinor" + $javaFileSuffix[$i]
                #$destination = $DestinationPath + "\" + $Filename
                $destination = $DestinationPath + "\" + $Version + "\" + $Filename

                $ExtensionType = [System.IO.Path]::GetExtension($fileName)

                If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                    Write-LogEntry ("File found: [{0}]. Ignoring download" -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                }
                Else{
                    ## -------- DOWNLOAD SOFTWARE ----------
                    If((Test-Path $destination -ErrorAction SilentlyContinue) -and $Overwrite){$OverwriteMsg = "File found, Overwriting! "}Else{$OverwriteMsg = ""}
                    Try{
                        Write-LogEntry ("{0}Attempting to download: [{1}]..." -f $OverwriteMsg,$Filename) -Severity 1 -Source ${CmdletName} -Outhost

                        Initialize-FileDownload -Name ("{0}" -f $Filename)  -Url $DownloadLink -TargetDest $destination
                        #$wc.DownloadFile($link, $destination) 
                        Write-LogEntry ("Succesfully downloaded: {0} [{1} Update {2}] to [{3}]" -f $Product,$JavaMajor,$JavaMinor,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                        $downloaded=$True
                    } 
                    Catch {
                        Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                        $downloaded=$False
                    }
                }

                #Build Object if exists
                If(Test-Path $destination){

                    #grab the date on the file 
                    $CreatedDate = Get-ChildItem $destination | Select-Object -ExpandProperty CreationTime | Get-Date -f "yyyy-MM-dd"
                    $FileSize = Get-FileSize $destination
                    
                    #build array of software for inventory
                    $SoftObject += new-object psobject -property @{
                        FilePath=$destination
                        Version=$Version
                        File=$Filename
                        Publisher=$Publisher
                        Product=$Product
                        Arch=$archLabel[$i]
                        Language=$Language
                        FileType=$ExtensionType
                        ProductType=$ProductType
                        Downloaded=$downloaded
                        Description=$Description
                        DownloadDate=$CreatedDate
                        Size=$FileSize
                    }
                }
                $i++
            }
        }
        catch {
            Write-LogEntry ("Unable to download [{0}]. {1} Check Line: {2}" -f $Product,$_.Exception.Message,$_.InvocationInfo.ScriptLineNumber)  -Severity 3 -Source ${CmdletName} -Outhost
        }
    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }
    

}


# JDK - DOWNLOAD
#==================================================
Function Get-JDK {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,

        [parameter(Mandatory=$false)]
        [string]$FolderPath,
        
        [parameter(Mandatory=$false)]
        [switch]$Overwrite,

        [parameter(Mandatory=$false)]
        [switch]$Cleanup,

        [parameter(Mandatory=$false)]
        [switch]$ReturnDetails 
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        $Publisher = "Oracle"
        $Product = "Java Development Toolkit"
        $Language = 'en'
        $ProductType = 'jdk'

        If(!$FolderPath){$FolderPath = $Product}

        [System.Uri]$SourceURL = "https://www.oracle.com"
        [System.Uri]$DownloadURL = "https://www.oracle.com/technetwork/java/javase/downloads/index.html"
        # https://download.oracle.com/otn-pub/java/jdk/12.0.1+12/69cfe15208a647278a19ef0990eea691/jdk-12.0.1_windows-x64_bin.exe

        Try{
            ## -------- CRAWL SOURCE ----------
            $content = Invoke-WebRequest $SourceURL -ErrorAction Stop -UseBasicParsing
            Start-Sleep 3
            
            ## -------- PARSE DESCRIPTION ----------
            $Description = Get-WebContentHeader -WebContent $content -Property Description

             ## -------- CRAWL DOWNLOAD SOURCE ----------
            $DownloadContent = Invoke-WebRequest $DownloadURL -ErrorAction Stop -UseBasicParsing

            ## -------- CRAWL LINK FOR VERSION ----------
            $DetailLink = $SourceURL.OriginalString + (Get-HrefMatches -content [string]$DownloadContent | Where-Object {$_ -like "*$ProductType*"} | Select-Object -First 1)
            $DetailContent = Invoke-WebRequest $DetailLink -ErrorAction Stop -UseBasicParsing
            $ProductVersion = $DetailContent.RawContent | Select-String -Pattern "$ProductType\s+.*?(\d+\.)(\d+\.)(\d+)" -AllMatches | Select-Object -ExpandProperty matches | Select-Object -ExpandProperty value
            $Version = ($ProductVersion -replace $ProductType,"").Trim()

            Write-LogEntry ("{0}'s latest version is: [{1} Update {2}]" -f $Product,$JavaMajor,$JavaMinor) -Severity 1 -Source ${CmdletName} -Outhost

            ## -------- FIND DOWNLOAD LINKS ----------
            #get the appropiate url based on architecture
            $ParseLinks = $DetailContent.RawContent | Select-String -Pattern "(http[s]?|[s]?)(:\/\/)([^\s,]+)" -AllMatches | Select-Object -ExpandProperty matches | Select-Object -ExpandProperty value
            $DownloadLinks = ($ParseLinks | Where-Object{$_ -match "_windows-x64_bin.exe"}) -replace '"',""

            ## -------- BUILD FOLDERS ----------
            $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
            If( !(Test-Path $DestinationPath)){
                New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
            }

            #Remove all folders and files except the latest if they exist
            If($Cleanup){
                Get-ChildItem -Path $DestinationPath -Exclude sites.exception | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
                    Remove-Item $_.fullname -Recurse -Force | Out-Null
                    Write-LogEntry ("Removed File: [{0}]" -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
                }
            }

            #build Destination folder based on version
            New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null

            
            Foreach ($link in $DownloadLinks){
    
                #build Download link from Root URL (if Needed)
                $DownloadLink = $link
                Write-LogEntry ("Validating Download Link: [{0}]" -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

                $Filename = Split-Path $DownloadLink -leaf

                $destination = $DestinationPath + "\" + $Version + "\" + $Filename

                $ExtensionType = [System.IO.Path]::GetExtension($fileName)

                If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                    Write-LogEntry ("File found: [{0}]. Ignoring download" -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                }
                Else{
                    ## -------- DOWNLOAD SOFTWARE ----------
                    If((Test-Path $destination -ErrorAction SilentlyContinue) -and $Overwrite){$OverwriteMsg = "File found, Overwriting! "}Else{$OverwriteMsg = ""}
                    Try{
                        Write-LogEntry ("{0}Attempting to download: [{1}]..." -f $OverwriteMsg,$Filename) -Severity 1 -Source ${CmdletName} -Outhost

                        Initialize-FileDownload -Name ("{0}" -f $Filename)  -Url $DownloadLink -TargetDest $destination
                        #$wc.DownloadFile($link, $destination) 
                        Write-LogEntry ("Succesfully downloaded: {0} [{1}] to [{2}]" -f $Product,$Version,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                        $downloaded=$True
                    } 
                    Catch {
                        Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                        $downloaded=$False
                    }
                }

                #Build Object if exists
                If(Test-Path $destination){
                    #grab the date on the file 
                    $CreatedDate = Get-ChildItem $destination | Select-Object -ExpandProperty CreationTime | Get-Date -f "yyyy-MM-dd"
                    $FileSize = Get-FileSize $destination

                    #build array of software for inventory
                    $SoftObject += new-object psobject -property @{
                        FilePath=$destination
                        Version=$Version
                        File=$Filename
                        Publisher=$Publisher
                        Product=$Product
                        Arch="x64"
                        Language=$Language
                        FileType=$ExtensionType
                        ProductType=$ProductType
                        Downloaded=$downloaded
                        Description=$Description
                        DownloadDate=$CreatedDate
                        Size=$FileSize
                    }
                }
                $i++
            }
        }
        catch {
            Write-LogEntry ("Unable to download [{0}]. {1} Check Line: {2}" -f $Product,$_.Exception.Message,$_.InvocationInfo.ScriptLineNumber)  -Severity 3 -Source ${CmdletName} -Outhost
        }
    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }
    

}

# Chrome (x86 & x64) - DOWNLOAD
#==================================================
Function Get-Chrome {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,

        [parameter(Mandatory=$true)]
        [string]$FolderPath,
        
        [parameter(Mandatory=$false)]
        [ValidateSet('Enterprise (x86)', 'Enterprise (x64)', 'Enterprise (Both)','Standalone (x86)','Standalone (x64)','Standalone (Both)')]
        [string]$ArchType,

        [parameter(Mandatory=$false)]
        [switch]$Overwrite,

        [parameter(Mandatory=$false)]
        [switch]$Cleanup,

        [parameter(Mandatory=$false)]
        [switch]$ReturnDetails 
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        $Publisher = "Google"
        $Product = "Chrome"
        #$Language = 'en'
        
        Try{
            #[System.Uri]$SourceURL = "https://cloud.google.com/chrome-enterprise/browser/download/?h1=$Language"
            [System.Uri]$SourceURL = "https://www.google.com/chrome/"
            [String]$DownloadURL = "https://dl.google.com/dl/chrome/install"
            #[System.Uri]$VersionURL = "https://www.whatismybrowser.com/guides/the-latest-version/chrome"
            [System.Uri]$VersionURL = "https://chromereleases.googleblog.com/2019/05/stable-channel-update-for-desktop.html"
            
            ## -------- CRAWL SOURCE ----------
            $content = Invoke-WebRequest $SourceURL -ErrorAction Stop

            ## -------- PARSE DESCRIPTION ----------
            $Description = Get-WebContentHeader -WebContent $content -Property Description

            ## -------- CRAWL VERSION SOURCE ----------
            $content = Invoke-WebRequest $VersionURL -ErrorAction Stop
            ($content.AllElements | Where-Object{$_.itemprop -eq 'articleBody'} | Select-Object -first 1) -match '(\d+\.)(\d+\.)(\d+\.)(\d+)' | Out-null
            $Version = $matches[0]
            
            #old way
            #$GetVersion = ($content.AllElements | Select-Object -ExpandProperty outerText  | Select-String '^(\d+\.)(\d+\.)(\d+\.)(\d+)' | Select-Object -first 1).ToString()
            #$Version = $GetVersion.Trim()
            Write-LogEntry ("{0}'s latest version is: [{1}]" -f $Product,$Version) -Severity 1 -Source ${CmdletName} -Outhost

            ## -------- BUILD DOWNLOAD LINKS ----------
            #get the appropiate url based on architecture and type
            switch($ArchType){
                'Enterprise (x86)' {$DownloadLinks = "$DownloadURL/googlechromestandaloneenterprise.msi"}
                'Enterprise (x64)' {$DownloadLinks = "$DownloadURL/googlechromestandaloneenterprise64.msi"}

                'Enterprise (Both)' {$DownloadLinks = "$DownloadURL/googlechromestandaloneenterprise64.msi",
                                                        "$DownloadURL/googlechromestandaloneenterprise.msi"}

                'Standalone (x86)' {$DownloadLinks = "$DownloadURL/ChromeStandaloneSetup.exe"}
                'Standalone (x64)' {$DownloadLinks = "$DownloadURL/ChromeStandaloneSetup64.exe"}

                'Standalone (Both)' {$DownloadLinks = "$DownloadURL/ChromeStandaloneSetup64.exe",
                                                        "$DownloadURL/ChromeStandaloneSetup.exe"}

                default {$DownloadLinks = "$DownloadURL/googlechromestandaloneenterprise64.msi",
                                        "$DownloadURL/googlechromestandaloneenterprise.msi",
                                        "$DownloadURL/ChromeStandaloneSetup64.exe",
                                        "$DownloadURL/ChromeStandaloneSetup.exe"
                        }
            }

            ## -------- BUILD FOLDERS ----------
            $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
            If( !(Test-Path $DestinationPath)){
                New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
            }

            #Remove all folders and files except the latest if they exist
            If($Cleanup){
                Get-ChildItem -Path $DestinationPath -Exclude disableupdates.bat | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
                    Remove-Item $_.fullname -Recurse -Force | Out-Null
                    Write-LogEntry ("Removed File: [{0}]" -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
                }
            }

            #build Destination folder based on version
            New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null

            
            Foreach ($link in $DownloadLinks){
                
                #build Download link from Root URL (if Needed)
                $DownloadLink = $link
                Write-LogEntry ("Validating Download Link: [{0}]..." -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

                $Filename = $DownloadLink | Split-Path -Leaf
                $destination = $DestinationPath + "\" + $Version + "\" + $Filename
            
                #find what arch the file is based on the integer 64
                $pattern = "\d{2}"
                $Filename -match $pattern | Out-Null

                #if match is found, set label
                If($matches){
                    $ArchLabel = "x64"
                }Else{
                    $ArchLabel = "x86"
                }
            
                # Determine if its enterprise download (based on file name)
                $pattern = "(?<text>.*enterprise*)"
                $Filename -match $pattern | Out-Null
                If($matches.text){
                    $ProductType = "Enterprise"
                }Else{
                    $ProductType = "Standalone"
                }

                #clear matches
                $matches = $null

                $ExtensionType = [System.IO.Path]::GetExtension($fileName)

                If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                    Write-LogEntry ("File found: [{0}]. Ignoring download" -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                }
                Else{
                    ## -------- DOWNLOAD SOFTWARE ----------
                    If((Test-Path $destination -ErrorAction SilentlyContinue) -and $Overwrite){$OverwriteMsg = "File found, Overwriting! "}Else{$OverwriteMsg = ""}
                    Try{
                        Write-LogEntry ("{0}Attempting to download: [{1}]..." -f $OverwriteMsg,$Filename) -Severity 1 -Source ${CmdletName} -Outhost

                        Initialize-FileDownload -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                        #$wc.DownloadFile($link, $destination) 
                        Write-LogEntry ("Succesfully downloaded: {0} {1} ({2}) to [{3}]" -f $Product,$ProductType,$ArchLabel,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                        $downloaded=$True
                    } 
                    Catch {
                        Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                        $downloaded=$False
                    }
                }

                #Build Object if exists
                If(Test-Path $destination){
                    #grab the date on the file 
                    $CreatedDate = Get-ChildItem $destination | Select-Object -ExpandProperty CreationTime | Get-Date -f "yyyy-MM-dd"
                    $FileSize = Get-FileSize $destination
                    
                    #build array of software for inventory
                    $SoftObject += new-object psobject -property @{
                        FilePath=$destination
                        Version=$Version
                        File=$Filename
                        Publisher=$Publisher
                        Product=$Product
                        Arch=$ArchLabel
                        Language=''
                        FileType=$ExtensionType
                        ProductType=$ProductType
                        Downloaded=$downloaded
                        Description=$Description
                        DownloadDate=$CreatedDate
                        Size=$FileSize
                    }
                }
            }
        }
        catch {
            Write-LogEntry ("Unable to download [{0}]. {1} Check Line: {2}" -f $Product,$_.Exception.Message,$_.InvocationInfo.ScriptLineNumber)  -Severity 3 -Source ${CmdletName} -Outhost
        }
    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }

}


# Firefox (x86 & x64) - DOWNLOAD
#==================================================
Function Get-Firefox {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,

        [parameter(Mandatory=$true)]
        [string]$FolderPath,
        
        [parameter(Mandatory=$false)]
        [ValidateSet('x86', 'x64')]
        [string]$Arch,

        [parameter(Mandatory=$false)]
        [ValidateSet('Latest','Nightly','Dev','Beta','ESR')]
        [string]$Type,

        [parameter(Mandatory=$false)]
        [ValidateSet('exe','msi')]
        [string]$Installer,

        [parameter(Mandatory=$false)]
        [switch]$Overwrite,

        [parameter(Mandatory=$false)]
        [switch]$Cleanup,

        [parameter(Mandatory=$false)]
        [switch]$ReturnDetails 
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        $Publisher = "Mozilla"
        $Product = "Firefox"
        $Language = 'en-US'

        [System.Uri]$VersionURL = "https://product-details.mozilla.org/1.0/firefox_versions.json"
        [System.Uri]$DownloadURL = "https://www.mozilla.org/en-US/firefox/all/"

        Try{
            ## -------- CRAWL SOURCE ----------
            # Use basic parsing   
            $content = Invoke-WebRequest $DownloadURL -ErrorAction Stop -UseBasicParsing

            #$firefoxInfo = $content.AllElements | Where-Object{$_.id -eq $Language} | Select-Object -ExpandProperty outerHTML

            ## -------- PARSE DESCRIPTION ----------
            $Description = Get-WebContentHeader -WebContent $content -Property Description

            ## -------- PARSE VERSION FROM JSON ----------
            $convertjson = Invoke-RestMethod $VersionURL -ErrorAction Stop -UseBasicParsing 
            
            ## -------- BUILD SEARCH BY TYPE ---------
            #appends -msi- to querystring
            switch($Installer){
                'msi' {$QueryAdd = "-msi-";$AddExtension='msi'}
                'exe' {$QueryAdd = "-";$AddExtension='exe'}
                Default {$QueryAdd = "-";$AddExtension='exe'}
            }

            #build querystring
            switch($Type){
                'Latest'    {$QueryString = "*firefox" + $QueryAdd + "latest*";$Version = $convertjson.LATEST_FIREFOX_VERSION}
                'Nightly'   {$QueryString = "*nightly" + $QueryAdd + "latest*";$Version = $convertjson.FIREFOX_NIGHTLY}
                'Dev'       {$QueryString = "*devedition" + $QueryAdd + "latest*";$Version = $convertjson.FIREFOX_DEVEDITION}
                'ESR'       {$QueryString = "*esr" + $QueryAdd + "latest*";$Version = $convertjson.FIREFOX_ESR}
                'Beta'      {$QueryString = "*beta" + $QueryAdd + "latest*";$Version = $convertjson.LATEST_FIREFOX_RELEASED_DEVEL_VERSION}
                Default     {$QueryString = "*latest*";$Version = $convertjson.LATEST_FIREFOX_VERSION}
            }

            #log message based on type
            If($null -eq $Type -or $Type -eq 'Latest'){
                Write-LogEntry ("{0}'s latest version is: [{1}]" -f $Product,$Version) -Severity 1 -Source ${CmdletName} -Outhost
            }
            Else{
                Write-LogEntry ("{0}'s [{1}] version is: [{2}]" -f $Product,$Type,$Version) -Severity 1 -Source ${CmdletName} -Outhost
            }

            ## -------- FIND DOWNLOAD LINKS BY ARCH ----------
            switch($Arch){
                'x86' {$DownloadLinks = Get-HrefMatches -content $content | Where-Object{$_ -like $QueryString -and $_ -like "*$Language" -and $_ -like "*win*"}}
                'x64' {$DownloadLinks = Get-HrefMatches -content $content | Where-Object{$_ -like $QueryString -and $_ -like "*$Language" -and$_ -like "*win64*"}}
                default {$DownloadLinks = Get-HrefMatches -content $content | Where-Object{$_ -like $QueryString -and $_ -like "*$Language" -and$_ -like "*win*"}}
            }



            ## -------- BUILD ROOT FOLDER ----------
            $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
            If( !(Test-Path $DestinationPath)){
                New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
            }
            
            ## -------- CLEANUP OLD VERSION FOLDERS ----------
            #Remove all folders and files except the latest if they exist
            If($Cleanup){
                Get-ChildItem -Path $DestinationPath -Exclude mms.cfg,disableupdates.bat | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
                    Remove-Item $_.fullname -Recurse -Force | Out-Null
                    Write-LogEntry ("Removed File: [{0}]" -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
                }
            }

            ## -------- BUILD NEW VERSION FOLDER ----------
            #build Destination folder based on version
            New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null

            #loop though each link to download
            Foreach($link in $DownloadLinks){
                
                #build Download link from Root URL (if Needed)
                $DownloadLink = $link
                Write-LogEntry ("Validating Download Link: [{0}]" -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

                #find the version for each link
                switch -regex ($link){
                    'firefox-latest'         {$Version = $convertjson.LATEST_FIREFOX_VERSION}
                    'firefox-nightly'        {$Version = $convertjson.FIREFOX_NIGHTLY}
                    'firefox-devedition'     {$Version = $convertjson.FIREFOX_DEVEDITION}
                    'firefox-esr'            {$Version = $convertjson.FIREFOX_ESR}
                    'firefox-beta'           {$Version = $convertjson.LATEST_FIREFOX_RELEASED_DEVEL_VERSION}
                }

                If ($link -like "*win64*"){
                    $Filename = ("Firefox Setup " + $Version + " (x64)." + $AddExtension)
                    $ArchLabel = "x64"
                }
                Else{
                    $Filename = ("Firefox Setup " + $Version + "." + $AddExtension)
                    $ArchLabel = "x86"
                }

                $ExtensionType = [System.IO.Path]::GetExtension($FileName)

                $destination = $DestinationPath + "\" + $Version + "\" + $Filename

                If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                    Write-LogEntry ("File found: [{0}]. Ignoring download" -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                }
                Else{
                    ## -------- DOWNLOAD SOFTWARE ----------
                    If((Test-Path $destination -ErrorAction SilentlyContinue) -and $Overwrite){$OverwriteMsg = "File found, Overwriting! "}Else{$OverwriteMsg = ""}
                    Try{
                        Write-LogEntry ("{0}Attempting to download: [{1}]..." -f $OverwriteMsg,$Filename) -Severity 1 -Source ${CmdletName} -Outhost

                        Initialize-FileDownload -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                        #$wc.DownloadFile($link, $destination) 
                        Write-LogEntry ("Succesfully downloaded: {0} ({1}) to [{2}]" -f $Product,$ArchLabel,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                        $downloaded=$True
                    } 
                    Catch {
                        Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                        $downloaded=$False
                    }
                }

                #Build Object if exists
                If(Test-Path $destination){
                    #grab the date on the file 
                    $CreatedDate = Get-ChildItem $destination | Select-Object -ExpandProperty CreationTime | Get-Date -f "yyyy-MM-dd"
                    $FileSize = Get-FileSize $destination
                    
                    #build array of software for inventory
                    $SoftObject += new-object psobject -property @{
                        FilePath=$destination
                        Version=$Version
                        File=$Filename
                        Publisher=$Publisher
                        Product=$Product
                        Arch=$ArchLabel
                        Language=$Language
                        FileType=$ExtensionType
                        ProductType=$ProductType
                        Downloaded=$downloaded
                        Description=$Description
                        DownloadDate=$CreatedDate
                        Size=$FileSize
                    }
                }
            }
        }
        catch {
            Write-LogEntry ("Unable to download [{0}]. {1} Check Line: {2}" -f $Product,$_.Exception.Message,$_.InvocationInfo.ScriptLineNumber)  -Severity 3 -Source ${CmdletName} -Outhost
        }
    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }
}

# Adobe Flash Active and Plugin - DOWNLOAD
#==================================================
Function Get-Flash {
    <#$distsource = "https://www.adobe.com/products/flashplayer/distribution5.html"
    #$ActiveXURL = "https://fpdownload.adobe.com/get/flashplayer/pdc/28.0.0.126/install_flash_player_28_active_x.msi"
    #$PluginURL = "https://fpdownload.adobe.com/get/flashplayer/pdc/28.0.0.126/install_flash_player_28_plugin.msi"
    #$PPAPIURL = "https://fpdownload.adobe.com/get/flashplayer/pdc/28.0.0.126/install_flash_player_28_ppapi.msi"
    #>
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,

        [parameter(Mandatory=$true)]
        [string]$FolderPath,

        [parameter(Mandatory=$false)]
        [ValidateSet('IE', 'Firefox', 'Chrome')]
        [string]$BrowserSupport,

        [parameter(Mandatory=$false)]
        [switch]$Overwrite,

        [parameter(Mandatory=$false)]
        [switch]$Cleanup,

        [parameter(Mandatory=$false)]
        [switch]$KillBrowsers,

        [parameter(Mandatory=$false)]
        [switch]$ReturnDetails 
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        $Publisher = "Adobe"
        $Product = "Flash"

        [System.Uri]$SourceURL = "https://get.adobe.com/flashplayer/"
        [String]$DownloadURL = "https://fpdownload.adobe.com/get/flashplayer/pdc/"

        Try{
            ## -------- CRAWL SOURCE ----------
            #don't use basic parsing when getting elements
            $content = Invoke-WebRequest $SourceURL -ErrorAction Stop
            start-sleep 3

            ## -------- PARSE DESCRIPTION ----------
            $Description = Get-WebContentHeader -WebContent $content -Property Description
            
             ## -------- PARSE VERSION ----------
            $GetVersion = (($content.AllElements | Select-Object -ExpandProperty outerText | Select-String '^Version (\d+\.)(\d+\.)(\d+\.)(\d+)' | Select-Object -last 1) -split " ")[1]
            $Version = $GetVersion.Trim()
            Write-LogEntry ("{0}'s latest version is: [{1}]" -f $Product,$Version) -Severity 1 -Source ${CmdletName} -Outhost
            $MajorVer = $Version.Split('.')[0]
            
            ## -------- BUILD FOLDERS ----------
            $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
            If( !(Test-Path $DestinationPath)){
                New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
            }

            #Remove all folders and files except the latest if they exist
            If($Cleanup){
                Get-ChildItem -Path $DestinationPath -Exclude mms.cfg,disableupdates.bat | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
                    Remove-Item $_.fullname -Recurse -Force | Out-Null
                    Write-LogEntry ("Removed File: [{0}]" -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
                }
            }

            #build Destination folder based on version
            New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null

            ## -------- GET TYPE ----------
            switch($BrowserSupport){
                'IE' {$types = 'active_x'}
                'Firefox' {$types = 'plugin'}
                'Chrome' {$types = 'ppapi'}
                default {$types = 'active_x','plugin','ppapi'}
            }

            ## -------- DOWNLOAD SOFTWARE ----------
            Foreach ($type in $types){
                $Filename = "install_flash_player_"+$MajorVer+"_"+$type+".msi"
    
                #build Download link from Root URL (if Needed)
                $DownloadLink = $DownloadURL + $Version + "/" + $Filename
                Write-LogEntry ("Validating Download Link: [{0}]" -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

                $ExtensionType = [System.IO.Path]::GetExtension($fileName)

                #$destination = $DestinationPath + "\" + $Filename
                $destination = $DestinationPath + "\" + $Version + "\" + $Filename

                Write-LogEntry ("Validating Download Link: [{0}]..." -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

                If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                    Write-LogEntry ("File found: [{0}]. Ignored download" -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                }
                Else{
                    If((Test-Path $destination -ErrorAction SilentlyContinue) -and $Overwrite){$OverwriteMsg = "File found, Overwriting! "}Else{$OverwriteMsg = ""}
                    Try{
                        Write-LogEntry ("{0}Attempting to download: [{1}]..." -f $OverwriteMsg,$Filename) -Severity 1 -Source ${CmdletName} -Outhost

                        Initialize-FileDownload -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                        #$wc.DownloadFile($link, $destination) 
                        Write-LogEntry ("Succesfully downloaded: {0} ({1}) to [{2}]" -f $Product,$type,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                        $downloaded=$True
                    } 
                    Catch {
                        Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                        $downloaded=$False
                    }
                }


                If($KillBrowsers){
                    Get-Process "firefox" -ErrorAction SilentlyContinue | Stop-Process -Force
                    Get-Process "iexplore" -ErrorAction SilentlyContinue | Stop-Process -Force
                    Get-Process "chrome" -ErrorAction SilentlyContinue | Stop-Process -Force
                }

                #Build Object if exists
                If(Test-Path $destination){
                    #grab the date on the file 
                    $CreatedDate = Get-ChildItem $destination | Select-Object -ExpandProperty CreationTime | Get-Date -f "yyyy-MM-dd"
                    $FileSize = Get-FileSize $destination
                    
                    #build array of software for inventory
                    $SoftObject += new-object psobject -property @{
                        FilePath=$destination
                        Version=$Version
                        File=$Filename
                        Publisher=$Publisher
                        Product=$Product
                        Arch=''
                        Language=''
                        FileType=$ExtensionType
                        ProductType=$type
                        Downloaded=$downloaded
                        Description=$Description
                        DownloadDate=$CreatedDate
                        Size=$FileSize
                    }
                }
            }
        }
        catch {
            Write-LogEntry ("Unable to download [{0}]. {1} Check Line: {2}" -f $Product,$_.Exception.Message,$_.InvocationInfo.ScriptLineNumber)  -Severity 3 -Source ${CmdletName} -Outhost
        }
    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }
}


# Adobe Flash Active and Plugin - DOWNLOAD
#==================================================
Function Get-Shockwave {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,
        
        [parameter(Mandatory=$true)]
        [string]$FolderPath,

        [parameter(Mandatory=$false)]
        [ValidateSet('Full', 'Slim', 'MSI')]
        [string]$Type,
        
        [parameter(Mandatory=$false)]
        [switch]$Overwrite,
        
        [parameter(Mandatory=$false)]
        [switch]$Cleanup,

        [parameter(Mandatory=$false)]
        [switch]$KillBrowsers,

        [parameter(Mandatory=$false)]
        [switch]$ReturnDetails 
        
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        $Publisher = "Adobe"
        $Product = "Shockwave"

        [System.Uri]$SourceURL = "https://get.adobe.com/shockwave/"
        [System.Uri]$DownloadURL = "https://www.adobe.com/products/shockwaveplayer/distribution3.html"
  
        Try{
            ## -------- CRAWL SOURCE ----------
            #don't use basic parsing when getting elements
            $content = Invoke-WebRequest $SourceURL -ErrorAction Stop
            start-sleep 3

            ## -------- PARSE DESCRIPTION ----------
            $Description = Get-WebContentHeader -WebContent $content -Property Description
            
            ## -------- PARSE VERSION ----------
            $GetVersion = (($content.AllElements | Select-Object -ExpandProperty outerText | Select-String '^Version (\d+\.)(\d+\.)(\d+\.)(\d+)' | Select-Object -last 1) -split " ")[1]
            $Version = $GetVersion.Trim()
            Write-LogEntry ("{0}'s latest version is: [{1}]" -f $Product,$Version) -Severity 1 -Source ${CmdletName} -Outhost

            ## -------- CRAWL DOWNLOAD WEBSITE ----------
            $content = Invoke-WebRequest $DownloadURL -ErrorAction Stop -UseBasicParsing

            ## -------- BUILD ROOT FOLDER ----------
            $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
            If(!(Test-Path $DestinationPath)){
                New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null 
            }

            ## -------- CLEANUP OLD FOLDERS ----------
            #Remove all folders and files except the latest if they exist
            If($Cleanup){
                Get-ChildItem -Path $DestinationPath | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
                    Remove-Item $_.fullname -Recurse -Force | Out-Null
                    Write-LogEntry ("Removed File: [{0}]" -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
                }
            }

            ## -------- CREATE NEW UPDATE FOLDER ----------
            #build Destination folder based on version
            New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null

            ## -------- PARSE HYPERLINKS BY TYPE ----------
            switch($Type){
                'Full' {$shockwaveLinks = Get-HrefMatches -content [string]$content | Where-Object {$_ -like "*Full*"} | Select-Object -First 1}
                'Slim' {$shockwaveLinks = Get-HrefMatches -content [string]$content | Where-Object {$_ -like "*Slim*"} | Select-Object -First 1}
                'MSI' {$shockwaveLinks = Get-HrefMatches -content [string]$content | Where-Object {$_ -like "*MSI*"} | Select-Object -First 1}
                default {$shockwaveLinks = Get-HrefMatches -content [string]$content | Where-Object {$_ -like "*installer"} | Select-Object -First 3}
            }

            # loop through each link to download
            Foreach ($link in $shockwaveLinks){
                #build Download link from Root URL (if Needed)
                $DownloadLink = $SourceURL.OriginalString + $link
                Write-LogEntry ("Validating Download Link: [{0}]" -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

                #name file based on link url
                $filename = $link.replace("/go/sw_","sw_lic_")
            
                #add on extension based on name
                If($filename -match 'msi'){$filename=$filename + '.msi'}
                If($filename -match 'exe'){$filename=$filename + '.exe'}

                $ExtensionType = [System.IO.Path]::GetExtension($fileName)

                # Break up file name by underscore, sw_full_exe_installer
                $ProductType = $fileName.Split('_')[2]
            
                #$destination = $DestinationPath + "\" + $Filename
                $destination = $DestinationPath + "\" + $Version + "\" + $Filename

                Write-LogEntry ("Validating Download Link: [{0}]" -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost
            
                If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                    Write-LogEntry ("File found: [{0}]. Ignoring download" -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                }
                Else{
                     ## -------- DOWNLOAD SOFTWARE ----------
                    If((Test-Path $destination -ErrorAction SilentlyContinue) -and $Overwrite){$OverwriteMsg = "File found, Overwriting! "}Else{$OverwriteMsg = ""}
                    Try{
                        Write-LogEntry ("{0}Attempting to download: [{1}]..." -f $OverwriteMsg,$Filename) -Severity 1 -Source ${CmdletName} -Outhost

                        Initialize-FileDownload -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                        #$wc.DownloadFile($link, $destination) 
                        Write-LogEntry ("Succesfully downloaded: {0} ({1}) to [{2}]" -f $Product,$ProductType,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                        $downloaded=$True
                    } 
                    Catch {
                        Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                        $downloaded=$False
                    }
                }

                #Build Object if exists
                If(Test-Path $destination){
                    #grab the date on the file 
                    $CreatedDate = Get-ChildItem $destination | Select-Object -ExpandProperty CreationTime | Get-Date -f "yyyy-MM-dd"
                    $FileSize = Get-FileSize $destination
                    
                    #build array of software for inventory
                    $SoftObject += new-object psobject -property @{
                        FilePath=$destination
                        Version=$Version
                        File=$Filename
                        Publisher=$Publisher
                        Product=$Product
                        Arch=''
                        Language=''
                        FileType=$ExtensionType
                        ProductType=$ProductType
                        Downloaded=$downloaded
                        Description=$Description
                        DownloadDate=$CreatedDate
                        Size=$FileSize
                    }
                }

                If($KillBrowsers){
                    Get-Process "firefox" -ErrorAction SilentlyContinue | Stop-Process -Force
                    Get-Process "iexplore" -ErrorAction SilentlyContinue | Stop-Process -Force
                    Get-Process "chrome" -ErrorAction SilentlyContinue | Stop-Process -Force
                }
            }
        }
        catch {
            Write-LogEntry ("Unable to download [{0}]. {1} Check Line: {2}" -f $Product,$_.Exception.Message,$_.InvocationInfo.ScriptLineNumber)  -Severity 3 -Source ${CmdletName} -Outhost
        }
    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }
}


# Adobe Acrobat Reader DC - DOWNLOAD
#==================================================
Function Get-ReaderDC {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,

        [parameter(Mandatory=$true)]
        [string]$FolderPath,

        [parameter(Mandatory=$false)]
        [switch]$AllLangToo,
        
        [parameter(Mandatory=$false)]
        [switch]$UpdatesOnly,

        [parameter(Mandatory=$false)]
        [switch]$Overwrite,

        [parameter(Mandatory=$false)]
        [switch]$Cleanup,

        [parameter(Mandatory=$false)]
        [switch]$KillBrowsers,

        [parameter(Mandatory=$false)]
        [switch]$ReturnDetails 
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        [string]$Publisher = "Adobe"
        [string]$Product = "Acrobat Reader"
        #[string]$FilePrefix = "AcroRdr"

        [System.Uri]$SourceURL = "https://supportdownloads.adobe.com/product.jsp?product=10&platform=Windows"
        [string]$DownloadURL = "http://ardownload.adobe.com"

        Try{
            ## -------- CRAWL WEBSITE ----------
            #don't use basic parsing, find null
            $content = Invoke-WebRequest $SourceURL -ErrorAction Stop
            start-sleep 3
            $HtmlTable = ($content.ParsedHtml.getElementsByTagName('table') | Where-Object{$_.className -eq 'max'}).innerHTML

            ## -------- PARSE DESCRIPTION ----------
            $Description = Get-WebContentHeader -WebContent $content -Property Description
            
            ## -------- PARSE VERSION ----------
            [string]$Version = (($content.AllElements | Select-Object -ExpandProperty outerText | Select-String "^Version*" | Select-Object -First 1) -split " ")[1]

            ## -------- PARSE LINKS ----------
            $Hyperlinks = Get-Hyperlinks -content [string]$HtmlTable

            ## -------- PARSE FOR UPDATE ----------
            switch($UpdatesOnly){
                $false {
                            #Break down version to major and minor
                            [version]$VersionDataType = $Version
                            [string]$MajorVersion = $VersionDataType.Major
                            [string]$MinorVersion = $VersionDataType.Minor
                            [string]$MainVersion = $MajorVersion + '.' + $MinorVersion

                            If($AllLangToo){[int32]$selectNum = 2}Else{[int32]$selectNum = 1};
                            $DownloadLinks = $Hyperlinks | Where-Object {$_.Text -like "*$Product*"} | Select-Object -First $selectNum
                            $LogComment = "$Publisher $Product`'s latest version is: [$MainVersion] and patch version is: [$Version]"
                        }

                $true {
                            If($AllLangToo){[int32]$selectNum = 2}Else{[int32]$selectNum = 1};
                            $DownloadLinks = $Hyperlinks | Where-Object {$_.Text -like "*$Product*"} | Select-Object -First $selectNum
                            $LogComment = "$Publisher $Product`'s latest Patch version is: [$Version]"
                        }
            }
            Write-LogEntry ("{0}" -f $LogComment) -Severity 1 -Source ${CmdletName} -Outhost

            ## -------- BUILD ROOT FOLDER ----------
            $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
            If( !(Test-Path $DestinationPath)){
                New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
            }

            ## -------- CLEANUP OLD VERSIONS ----------
            #Remove all folders and files except the latest if they exist
            If($Cleanup){
                Get-ChildItem -Path $DestinationPath | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
                    Remove-Item $_.fullname -Recurse -Force | Out-Null
                    Write-LogEntry ("Removed File: [{0}]" -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
                }
            }

            #build Destination folder based on version
            New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null

            #loop through each link to download
            Foreach($link in $DownloadLinks){

                If($null -ne $SourceURL.PathAndQuery){
                    $DetailSource = (($SourceURL.OriginalString).replace($SourceURL.PathAndQuery ,"") + '/' + $link.Href)
                }
                Else{
                    $DetailSource = ($SourceURL.OriginalString + '/' + $link.Href)
                }
                ## -------- CRAWL DOWNLOAD LINK ----------
                #don't use basic parsing wwn crawling html
                $DetailContent = Invoke-WebRequest $DetailSource -ErrorAction Stop
                start-sleep 3
                
                #grab final download link
                $DetailInfo = $DetailContent.AllElements | Select-Object -ExpandProperty outerHTML 
                
                $DownloadConfirmLink = Get-HrefMatches -content [string]$DetailInfo | Where-Object {$_ -like "thankyou.jsp*"} | Select-Object -First 1
                $DownloadSource = (($SourceURL.OriginalString).replace($SourceURL.PathAndQuery ,"") + '/' + $DownloadConfirmLink).Replace("&amp;","&")

                #use basic parsing
                $DownloadContent = Invoke-WebRequest $DownloadSource -UseBasicParsing
                
                #build Download link from Root URL (if Needed)
                $DownloadLink = Get-HrefMatches -content [string]$DownloadContent | Where-Object {$_ -like "$DownloadURL/*"} | Select-Object -First 1
                Write-LogEntry ("Validating Download Link: [{0}]" -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost
            
                $Filename = $DownloadLink | Split-Path -Leaf
                $ExtensionType = [System.IO.Path]::GetExtension($fileName)
            
                If($Filename -match 'MUI'){
                    $ProductType = 'MUI'
                } 
                Else {
                    $ProductType = ''
                }

                #Adobe's versioning does not include dots (.) or the first two digits
                #$fileversion = $Version.replace('.','').substring(2)

                #$destination = $DestinationPath + "\" + $Filename
                $destination = $DestinationPath + "\" + $Version + "\" + $Filename

                
                If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                    Write-LogEntry ("File found: [{0}]. Ignoring download" -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                }
                Else{
                    ## -------- DOWNLOAD SOFTWARE ----------
                    If((Test-Path $destination -ErrorAction SilentlyContinue) -and $Overwrite){$OverwriteMsg = "File found, Overwriting! "}Else{$OverwriteMsg = ""}
                    Try{
                        Write-LogEntry ("{0}Attempting to download: [{1}]..." -f $OverwriteMsg,$Filename) -Severity 1 -Source ${CmdletName} -Outhost

                        Initialize-FileDownload -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                        #$wc.DownloadFile($link, $destination) 
                        Write-LogEntry ("Succesfully downloaded: {0} ({1}) to [{2}]" -f $Product,$ProductType,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                        $downloaded=$True
                    } 
                    Catch {
                        Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                        $downloaded=$False
                    }
                }

                #Build Object if exists
                If(Test-Path $destination){
                    #grab the date on the file 
                    $CreatedDate = Get-ChildItem $destination | Select-Object -ExpandProperty CreationTime | Get-Date -f "yyyy-MM-dd"
                    $FileSize = Get-FileSize $destination
                    
                    #build array of software for inventory
                    $SoftObject += new-object psobject -property @{
                        FilePath=$destination
                        Version=$Version
                        File=$Filename
                        Publisher=$Publisher
                        Product=$Product
                        Arch=''
                        Language=''
                        FileType=$ExtensionType
                        ProductType=$ProductType
                        Downloaded=$downloaded
                        Description=$Description
                        DownloadDate=$CreatedDate
                        Size=$FileSize
                    }
                }

                If($KillBrowsers){
                    Get-Process "firefox" -ErrorAction SilentlyContinue | Stop-Process -Force
                    Get-Process "iexplore" -ErrorAction SilentlyContinue | Stop-Process -Force
                    Get-Process "chrome" -ErrorAction SilentlyContinue | Stop-Process -Force
                }

            }
        }
        catch {
            Write-LogEntry ("Unable to download [{0}]. {1} Check Line: {2}" -f $Product,$_.Exception.Message,$_.InvocationInfo.ScriptLineNumber)  -Severity 3 -Source ${CmdletName} -Outhost
        }
    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }
}

# Adobe Reader Full Release - DOWNLOAD
#==================================================
Function Get-Reader{
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,

        [parameter(Mandatory=$true)]
        [string]$FolderPath,

        [parameter(Mandatory=$false)]
        [switch]$AllLangToo,

        [parameter(Mandatory=$false)]
        [switch]$UpdatesOnly,

        [parameter(Mandatory=$false)]
        [switch]$Overwrite,

        [parameter(Mandatory=$false)]
        [switch]$Cleanup,

        [parameter(Mandatory=$false)]
        [switch]$ReturnDetails 
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name

    }
    Process
    {
        $SoftObject = @()
        
        [string]$Publisher = "Adobe"
        [string]$Product = "Reader"
        #[string]$FilePrefix = "AdbeRdr"
        
        
        [System.Uri]$SourceURL = "http://www.adobe.com/support/downloads/product.jsp?product=10&platform=Windows"
        [string]$LastVersion = '11'
        [string]$DownloadURL = "http://ardownload.adobe.com"

        Try{
            ## -------- CRAWL SOURCE ----------
            $content = Invoke-WebRequest $SourceURL -ErrorAction Stop 
            start-sleep 3
            $HtmlTable = ($content.ParsedHtml.getElementsByTagName('table') | Where-Object{$_.className -eq 'max'}).innerHTML

            ## -------- PARSE DESCRIPTION ----------
            $Description = Get-WebContentHeader -WebContent $content -Property Description

            ## --------PARSE HYPERLINKS ----------
            $Hyperlinks = Get-Hyperlinks -content [string]$HtmlTable

            ## --------PARSE VERSION ----------
            [string]$Version = (($content.AllElements | Select-Object -ExpandProperty outerText | Select-String "^Version $LastVersion*" | Select-Object -First 1) -split " ")[1]
            [version]$VersionDataType = $Version
            [string]$MajorVersion = $VersionDataType.Major
            [string]$MinorVersion = $VersionDataType.Minor
            [string]$MainVersion = $MajorVersion + '.' + $MinorVersion
            
            ## -------- BUILD ROOT FOLDER ----------
            $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
            If( !(Test-Path $DestinationPath)){
                New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
            }

            ## -------- CLEANUP OLD VERSION FOLDERS ----------
            #Remove all folders and files except the latest if they exist
            If($Cleanup){
                Get-ChildItem -Path $DestinationPath | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
                    Remove-Item $_.fullname -Recurse -Force | Out-Null
                    Write-LogEntry ("Removed File: [{0}]" -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
                }
            }

            ## -------- BUILD VERSION FOLDER ----------
            #build Destination folder based on version
            New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null

            switch($UpdatesOnly){
                $false {
                            If($AllLangToo){[int32]$selectNum = 3}Else{[int32]$selectNum = 2};
                            $DownloadLinks = $Hyperlinks | Where-Object {$_.Text -like "$Publisher $Product $MainVersion*"} | Select-Object -First $selectNum
                            $LogComment = "$Publisher $Product`'s latest version is: [$MainVersion] and patch version is: [$Version]"
                        }

                $true {
                            If($AllLangToo){[int32]$selectNum = 2}Else{[int32]$selectNum = 1};
                            $DownloadLinks = $Hyperlinks | Where-Object {$_.Text -like "*$Version update*"} | Select-Object -First $selectNum
                            $LogComment = "$Publisher $Product`'s latest Patch version is: [$Version]"
                        }
                default {
                            If($AllLangToo){[int32]$selectNum = 2}Else{[int32]$selectNum = 1};
                            $DownloadLinks = $Hyperlinks | Where-Object {$_.Text -like "*$Version update*"} | Select-Object -First $selectNum
                            $LogComment = "$Publisher $Product`'s latest Patch version is: [$Version]"
                        }

            }

            Write-LogEntry ("{0}" -f $LogComment) -Severity 1 -Source ${CmdletName} -Outhost

            Foreach($link in $DownloadLinks){
                $DetailSource = ($DownloadURL + $link.Href)
                $DetailContent = Invoke-WebRequest $DetailSource -ErrorAction Stop
                start-sleep 3
                $DetailInfo = $DetailContent.AllElements | Select-Object -ExpandProperty outerHTML 
                
                #Grab name of file from html table
                #$DetailName = $DetailContent.AllElements | Select-Object -ExpandProperty outerHTML | Where-Object {$_ -like "*$FilePrefix*"} | Select-Object -Last 1
                #$PatchName = [string]$DetailName -replace "<[^>]*?>|<[^>]*>",""

                $DownloadConfirmLink = Get-HrefMatches -content [string]$DetailInfo | Where-Object {$_ -like "thankyou.jsp*"} | Select-Object -First 1
                $DownloadSource = ($DownloadURL + $DownloadConfirmLink).Replace("&amp;","&")
                
                $DownloadContent = Invoke-WebRequest $DownloadSource -ErrorAction Stop
                
                $DownloadLink = Get-HrefMatches -content [string]$DownloadContent | Where-Object {$_ -like "http://ardownload.adobe.com/*"} | Select-Object -First 1
                Write-LogEntry ("Validating Download Link: [{0}]" -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

                $Filename = $DownloadFinalLink | Split-Path -Leaf
                #$destination = $DestinationPath + "\" + $Filename
                $destination = $DestinationPath + "\" + $Version + "\" + $Filename

                $ExtensionType = [System.IO.Path]::GetExtension($fileName)

                If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                    Write-LogEntry ("File found: [{0}]. Ignoring download" -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                }
                Else{
                    ## -------- DOWNLOAD SOFTWARE ----------
                    If((Test-Path $destination -ErrorAction SilentlyContinue) -and $Overwrite){$OverwriteMsg = "File found, Overwriting! "}Else{$OverwriteMsg = ""}
                    Try{
                        Write-LogEntry ("{0}Attempting to download: [{1}]..." -f $OverwriteMsg,$Filename) -Severity 1 -Source ${CmdletName} -Outhost

                        Initialize-FileDownload -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                        #$wc.DownloadFile($link, $destination) 
                        Write-LogEntry ("Succesfully downloaded: {0} {1} to [{2}]" -f $Product,$ProductType,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                        $downloaded=$True

                        #if Path is a zipped installer, extract it
                        If($ExtensionType -match ".zip"){
                            $MajorPath = $DestinationPath + "\" + $MainVersion
                            New-Item -Path $MajorPath -Type Directory -ErrorAction SilentlyContinue | Out-Null
                            Expand-Archive $destination -DestinationPath $MajorPath | Out-Null
                        }
                    } 
                    Catch {
                        Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                        $downloaded=$False
                    }
                }

                #Build Object if exists
                If(Test-Path $destination){
                    #grab the date on the file 
                    $CreatedDate = Get-ChildItem $destination | Select-Object -ExpandProperty CreationTime | Get-Date -f "yyyy-MM-dd"
                    $FileSize = Get-FileSize $destination
                    
                    #build array of software for inventory
                    $SoftObject += new-object psobject -property @{
                        FilePath=$destination
                        Version=$Version
                        File=$Filename
                        Publisher=$Publisher
                        Product=$Product
                        Arch=''
                        Language=''
                        FileType=$ExtensionType
                        ProductType=$ProductType
                        Downloaded=$downloaded
                        Description=$Description
                        DownloadDate=$CreatedDate
                        Size=$FileSize
                    }
                }

            }
        }
        catch {
            Write-LogEntry ("Unable to download [{0}]. {1} Check Line: {2}" -f $Product,$_.Exception.Message,$_.InvocationInfo.ScriptLineNumber)  -Severity 3 -Source ${CmdletName} -Outhost
        }
    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }
}

# Adobe Acrobat DC Pro - DOWNLOAD
#==================================================
Function Get-AcrobatPro {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,

        [parameter(Mandatory=$true)]
        [string]$FolderPath,

        [parameter(Mandatory=$false)]
        [switch]$AllLangToo,

        [parameter(Mandatory=$false)]
        [switch]$Overwrite,

        [parameter(Mandatory=$false)]
        [switch]$Cleanup,

        [parameter(Mandatory=$false)]
        [switch]$KillBrowsers,

        [parameter(Mandatory=$false)]
        [switch]$ReturnDetails 
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        $Publisher = "Adobe"
        $Product = "Adobe Acrobat DC Pro"


        [string]$SourceURL = "https://supportdownloads.adobe.com/product.jsp?product=01&platform=Windows"
        [string]$DownloadURL = "http://ardownload.adobe.com"
        $SourceURI = [System.Uri]$SourceURL 

        Try{
             ## -------- CRAWL WEBSITE ----------
             #don't use basic parsing when getting html elements
             $content = Invoke-WebRequest $SourceURL -ErrorAction Stop
             start-sleep 3
             $HtmlTable = ($content.ParsedHtml.getElementsByTagName('table') | Where-Object{$_.className -eq 'max'}).innerHTML
 
             ## --------PARSE HYPERLINKS ----------
             $Hyperlinks = Get-Hyperlinks -content [string]$HtmlTable
 
             ## --------PARSE VERSION ----------        
            [string]$Version = (($content.AllElements | Select-Object -ExpandProperty outerText | Select-String "^Version*" | Select-Object -First 1) -split " ")[1]

            ## -------- BUILD ROOT FOLDER ----------
            $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
            If( !(Test-Path $DestinationPath)){
                New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
            }

            #Remove all folders and files except the latest if they exist
            If($Cleanup){
                Get-ChildItem -Path $DestinationPath | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
                    Remove-Item $_.fullname -Recurse -Force | Out-Null
                    Write-LogEntry ("Removed File: [{0}]" -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
                }
            }

            #build Destination folder based on version
            New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null

            ## -------- FILTER HYPERLINKS ----------
            $DownloadLinks = $Hyperlinks | Where-Object {$_.Text -like "$Product*"} | Select-Object -First 1
            $LogComment = "$Product`'s latest Patch version is: [$Version]"
            Write-LogEntry ("{0}" -f $LogComment) -Severity 1 -Source ${CmdletName} -Outhost

            Foreach($link in $DownloadLinks){
                If($null -ne $SourceURI.PathAndQuery){
                    $DetailSource = ($SourceURL.replace($SourceURI.PathAndQuery ,"") + '/' + $link.Href)
                }
                Else{
                    $DetailSource = ($SourceURL + '/' + $link.Href)
                }
                $DetailContent = Invoke-WebRequest $DetailSource -ErrorAction Stop
                start-sleep 3
        
                $DetailInfo = $DetailContent.AllElements | Select-Object -ExpandProperty outerHTML 
                $DetailVersion = $DetailContent.AllElements | Select-Object -ExpandProperty outerText | Select-String '^Version(\d+)'
                [string]$Version = $DetailVersion -replace "Version"
                
                #Grab name of file from html
                #$DetailName = $DetailContent.AllElements | Select-Object -ExpandProperty outerHTML | Where-Object {$_ -like "*AcroRdr*"} | Select-Object -Last 1
                #$PatchName = [string]$DetailName -replace "<[^>]*?>|<[^>]*>",""

                Write-LogEntry ("{0}'s latest version is: [{1}]" -f $Product,$Version) -Severity 1 -Source ${CmdletName} -Outhost

                $DownloadConfirmLink = Get-HrefMatches -content [string]$DetailInfo | Where-Object {$_ -like "thankyou.jsp*"} | Select-Object -First 1
                $DownloadSource = ($SourceURL.replace($SourceURI.PathAndQuery ,"") + '/' + $DownloadConfirmLink).Replace("&amp;","&")

                #use basic parsing
                $DownloadContent = Invoke-WebRequest $DownloadSource -UseBasicParsing
                
                #build Download link from Root URL (if Needed)
                $DownloadLink = Get-HrefMatches -content [string]$DownloadContent | Where-Object {$_ -like "$DownloadURL/*"} | Select-Object -First 1
                Write-LogEntry ("Validating Download Link: [{0}]" -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost
            
                $Filename = $DownloadLink | Split-Path -Leaf
                $ExtensionType = [System.IO.Path]::GetExtension($fileName)
            
                If($Filename -match 'MUI'){
                    $ProductType = 'MUI'
                } 
                Else {
                    $ProductType = ''
                }

                #Adobe's versioning does not include dots (.) or the first two digits
                #$fileversion = $Version.replace('.','').substring(2)

                #$destination = $DestinationPath + "\" + $Filename
                $destination = $DestinationPath + "\" + $Version + "\" + $Filename

                
                If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                    Write-LogEntry ("File found: [{0}]. Ignoring download" -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                }
                Else{
                    ## -------- DOWNLOAD SOFTWARE ----------
                    If((Test-Path $destination -ErrorAction SilentlyContinue) -and $Overwrite){$OverwriteMsg = "File found, Overwriting! "}Else{$OverwriteMsg = ""}
                    Try{
                        Write-LogEntry ("{0}Attempting to download: [{1}]..." -f $OverwriteMsg,$Filename) -Severity 1 -Source ${CmdletName} -Outhost

                        Initialize-FileDownload -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                        #$wc.DownloadFile($link, $destination) 
                        Write-LogEntry ("Succesfully downloaded: {0} ({1}) to [{2}]" -f $Product,$ProductType,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                        $downloaded=$True
                    } 
                    Catch {
                        Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                        $downloaded=$False
                    }
                }

                #Build Object if exists
                If(Test-Path $destination){
                    #grab the date on the file 
                    $CreatedDate = Get-ChildItem $destination | Select-Object -ExpandProperty CreationTime | Get-Date -f "yyyy-MM-dd"
                    $FileSize = Get-FileSize $destination
                    
                    #build array of software for inventory
                    $SoftObject += new-object psobject -property @{
                        FilePath=$destination
                        Version=$Version
                        File=$Filename
                        Publisher=$Publisher
                        Product=$Product
                        Arch=''
                        Language=''
                        FileType=$ExtensionType
                        ProductType=$ProductType
                        Downloaded=$downloaded
                        Description=$Description
                        DownloadDate=$CreatedDate
                        Size=$FileSize
                    }
                }

                If($KillBrowsers){
                    Get-Process "firefox" -ErrorAction SilentlyContinue | Stop-Process -Force
                    Get-Process "iexplore" -ErrorAction SilentlyContinue | Stop-Process -Force
                    Get-Process "chrome" -ErrorAction SilentlyContinue | Stop-Process -Force
                }

            }
        }
        catch {
            Write-LogEntry ("Unable to download [{0}]. {1} Check Line: {2}" -f $Product,$_.Exception.Message,$_.InvocationInfo.ScriptLineNumber)  -Severity 3 -Source ${CmdletName} -Outhost
        }
    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }
}

# Notepad Plus Plus - DOWNLOAD
#==================================================
Function Get-NotepadPlusPlus {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,

        [parameter(Mandatory=$true)]
        [string]$FolderPath,

        [parameter(Mandatory=$false)]
        [ValidateSet('x86', 'x64')]
        [string]$Arch,

        [parameter(Mandatory=$false)]
        [switch]$Overwrite,

        [parameter(Mandatory=$false)]
        [switch]$Cleanup,

        [parameter(Mandatory=$false)]
        [switch]$ReturnDetails 
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        $Publisher = "Notepad++"
        $Product = "Notepad++"

        [System.uri]$SourceURL = "https://notepad-plus-plus.org"
        [string]$DownloadURL = "https://notepad-plus-plus.org/download/v"

        Try{
            ## -------- CRAWL WEBSITE ----------
            #don't use basic web parsing when get html elements
            $content = Invoke-WebRequest $SourceURL -ErrorAction Stop
            start-sleep 3
            
            ## -------- PARSE DESCRIPTION ----------
            $Description = Get-WebContentHeader -WebContent $content -Property Description


            ## -------- PARSE VESION ----------
            $GetVersion = $content.AllElements | Where-Object{$_.id -eq "download"} | Select-Object -First 1 -ExpandProperty outerText
            $Version = $GetVersion.Split(":").Trim()[1]
            Write-LogEntry ("{0}'s latest version is: [{1}]" -f $Product,$Version) -Severity 1 -Source ${CmdletName} -Outhost
        
            ## -------- CRAWL DOWNLOAD SOURCE ----------
            $DownloadSource = ($DownloadURL + $Version + ".html")
            $DownloadContent = Invoke-WebRequest $DownloadSource -ErrorAction Stop

            $DownloadInfo = $DownloadContent.AllElements | Select-Object -ExpandProperty outerHTML 
            
            ## -------- BUILD ROOT FOLDER ----------
            $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
            If( !(Test-Path $DestinationPath)){
                New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
            }

            #Remove all folders and files except the latest if they exist
            If($Cleanup){
                Get-ChildItem -Path $DestinationPath | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
                    Remove-Item $_.fullname -Recurse -Force | Out-Null
                    Write-LogEntry ("Removed File: [{0}]" -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
                }
            }

            #build Destination folder based on version
            New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null

            switch($Arch){
                'x86' {$DownloadLinks = Get-HrefMatches -content [string]$DownloadInfo | Where-Object {($_ -like "*/repository/*") -and ($_ -like "*Installer*") -and ($_ -notlike "*.sig")} | Select-Object -First 1}
                'x64' {$DownloadLinks = Get-HrefMatches -content [string]$DownloadInfo | Where-Object {($_ -like "*/repository/*") -and ($_ -like "*Installer.x64*") -and ($_ -notlike "*.sig")} | Select-Object -Unique}
                default {$DownloadLinks = Get-HrefMatches -content [string]$DownloadInfo | Where-Object {($_ -like "*/repository/*") -and ($_ -like "*Installer*") -and ($_ -notlike "*.sig")} | Select-Object -Unique}
            }

            Foreach($link in $DownloadLinks){
                #build Download link from Root URL (if Needed)
                $DownloadLink = $SourceURL.OriginalString + $link
                Write-LogEntry ("Validating Download Link: [{0}]" -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

                $Filename = $link | Split-Path -Leaf
                $destination = $DestinationPath + "\" + $Version + "\" + $Filename

                #if match is found, set label
                If($Filename -match '.x64'){
                    $ArchLabel = "x64"
                }Else{
                    $ArchLabel = "x86"
                }

                $ExtensionType = [System.IO.Path]::GetExtension($fileName) 

                If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                    Write-LogEntry ("File found: [{0}]. Ignoring download" -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                }
                Else{
                    ## -------- DOWNLOAD SOFTWARE ----------
                    If((Test-Path $destination -ErrorAction SilentlyContinue) -and $Overwrite){$OverwriteMsg = "File found, Overwriting! "}Else{$OverwriteMsg = ""}
                    Try{
                        Write-LogEntry ("{0}Attempting to download: [{1}]..." -f $OverwriteMsg,$Filename) -Severity 1 -Source ${CmdletName} -Outhost

                        Initialize-FileDownload -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                        #$wc.DownloadFile($link, $destination) 
                        Write-LogEntry ("Succesfully downloaded: {0} ({1}) to [{2}]" -f $Product,$ArchLabel,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                        $downloaded=$True
                    } 
                    Catch {
                        Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                        $downloaded=$False
                    }
                }

                #Build Object if exists
                If(Test-Path $destination){
                    #grab the date on the file 
                    $CreatedDate = Get-ChildItem $destination | Select-Object -ExpandProperty CreationTime | Get-Date -f "yyyy-MM-dd"
                    $FileSize = Get-FileSize $destination
                    
                    #build array of software for inventory
                    $SoftObject += new-object psobject -property @{
                        FilePath=$destination
                        Version=$Version
                        File=$Filename
                        Publisher=$Publisher
                        Product=$Product
                        Arch=$ArchLabel
                        Language=''
                        FileType=$ExtensionType
                        ProductType=''
                        Downloaded=$downloaded
                        Description=$Description
                        DownloadDate=$CreatedDate
                        Size=$FileSize
                    }
                }
            }
        }
        catch {
            Write-LogEntry ("Unable to download [{0}]. {1} Check Line: {2}" -f $Product,$_.Exception.Message,$_.InvocationInfo.ScriptLineNumber)  -Severity 3 -Source ${CmdletName} -Outhost
        }
    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }

}

# 7zip - DOWNLOAD
#==================================================
Function Get-7Zip {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,

        [parameter(Mandatory=$true)]
        [string]$FolderPath,

        [parameter(Mandatory=$false)]
        [ValidateSet('EXE (x86)', 'EXE (x64)', 'EXE (Both)','MSI (x86)','MSI (x64)','MSI (Both)')]
        [string]$ArchVersion,

        [parameter(Mandatory=$false)]
        [switch]$Overwrite,

        [parameter(Mandatory=$false)]
        [switch]$Cleanup,

        [parameter(Mandatory=$false)]
        [switch]$Beta,

        [parameter(Mandatory=$false)]
        [switch]$ReturnDetails 
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        $Publisher = "7-Zip"
        $Product = "7-Zip"

        [System.Uri]$SourceURL = "http://www.7-zip.org"
        [System.Uri]$DownloadURL = "http://www.7-zip.org/download.html"

        Try{
            ## -------- CRAWL WEBSITE ----------
            #don't use basic web parsing when get html elements
            $content = Invoke-WebRequest $DownloadURL -ErrorAction Stop
            start-sleep 3

            ## -------- PARSE DESCRIPTION ----------
            $Description = Get-WebContentHeader -WebContent $content -Property Description

            ## -------- PARSE VESION ----------
            If($Beta){
                $GetVersion = $content.AllElements | Select-Object -ExpandProperty outerText | Where-Object {$_ -like "Download 7-Zip*"} | Where-Object {$_ -like "*:"} | Select-Object -First 1
            }
            Else{ 
                $GetVersion = $content.AllElements | Select-Object -ExpandProperty outerText | Where-Object {$_ -like "Download 7-Zip*"} | Where-Object {$_ -notlike "*beta*"} | Select-Object -First 1 
            }

            $Version = $GetVersion.Split(" ")[2].Trim()
            $FileVersion = $Version -replace '[^0-9]'
            Write-LogEntry ("{0}'s latest version is: [{1}]" -f $Product,$Version) -Severity 1 -Source ${CmdletName} -Outhost

            $Hyperlinks = Get-Hyperlinks -content [string]$content
            #$FilteredLinks = $Hyperlinks | Where-Object{$_.Href -like "*$FileVersion*"} | Where-Object {$_.Href -match '\.(exe|msi)$'}
           
            switch($ArchVersion){
                'EXE (x86)' {$DownloadLinks = $Hyperlinks | Where-Object{$_.Href -like "*$FileVersion*"} | Where-Object {$_.Href -match '\.(exe)$'} | Select-Object -First 1 }
                'EXE (x64)' {$DownloadLinks = $Hyperlinks | Where-Object{$_.Href -like "*$FileVersion-x64*"} | Where-Object {$_.Href -match '\.(exe)$'} | Select-Object -First 1 }

                'EXE (Both)' {$DownloadLinks = $Hyperlinks | Where-Object{$_.Href -like "*$FileVersion*"} | Where-Object {$_.Href -match '\.(exe)$'} | Select-Object -First 2 }

                'MSI (x86)' {$DownloadLinks = $Hyperlinks | Where-Object{$_.Href -like "*$FileVersion*"} | Where-Object {$_.Href -match '\.(msi)$'} | Select-Object -First 1 }
                'MSI (x64)' {$DownloadLinks = $Hyperlinks | Where-Object{$_.Href -like "*$FileVersion-x64*"} | Where-Object {$_.Href -match '\.(msi)$'} | Select-Object -First 1 }

                'MSI (Both)' {$DownloadLinks = $Hyperlinks | Where-Object{$_.Href -like "*$FileVersion*"} | Where-Object {$_.Href -match '\.(msi)$'} | Select-Object -First 2 }

                default {$DownloadLinks = $Hyperlinks | Where-Object{$_.Href -like "*$FileVersion*"} | Where-Object {$_.Href -match '\.(exe|msi)$'}}
            }

            ## -------- BUILD ROOT FOLDER ----------
            $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
            If( !(Test-Path $DestinationPath)){
                New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
            }

            #Remove all folders and files except the latest if they exist
            If($Cleanup){
                Get-ChildItem -Path $DestinationPath | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
                    Remove-Item $_.fullname -Recurse -Force | Out-Null
                    Write-LogEntry ("Removed File: [{0}]" -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
                }
            }

            #build Destination folder based on version
            New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null

            Foreach($link in $DownloadLinks){
                #build Download link from Root URL (if Needed)
                $DownloadLink = $SourceURL.OriginalString + "/" + $link.Href
                Write-LogEntry ("Validating Download Link: [{0}]" -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost
                
                $Filename = $DownloadLink | Split-Path -Leaf
                $destination = $DestinationPath + "\" + $Version + "\" + $Filename

                #find what arch the file is based on the integer 64
                $pattern = "(-x)(\d{2})"
                $Filename -match $pattern | Out-Null

                #if match is found, set label
                If($matches){
                    $ArchLabel = "x64"
                }Else{
                    $ArchLabel = "x86"
                }

                $matches = $null

                $ExtensionType = [System.IO.Path]::GetExtension($fileName)
            
                If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                    Write-LogEntry ("File found: [{0}]. Ignoring download" -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                }
                Else{
                    ## -------- DOWNLOAD SOFTWARE ----------
                    If((Test-Path $destination -ErrorAction SilentlyContinue) -and $Overwrite){$OverwriteMsg = "File found, Overwriting! "}Else{$OverwriteMsg = ""}
                    Try{
                        Write-LogEntry ("{0}Attempting to download: [{1}]..." -f $OverwriteMsg,$Filename) -Severity 1 -Source ${CmdletName} -Outhost

                        Initialize-FileDownload -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                        #$wc.DownloadFile($link, $destination) 
                        Write-LogEntry ("Succesfully downloaded: {0} ({1}) to [{2}]" -f $Product,$ArchLabel,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                        $downloaded=$True
                    } 
                    Catch {
                        Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                        $downloaded=$False
                    }
                }

                #Build Object if exists
                If(Test-Path $destination){
                    #grab the date on the file 
                    $CreatedDate = Get-ChildItem $destination | Select-Object -ExpandProperty CreationTime | Get-Date -f "yyyy-MM-dd"
                    $FileSize = Get-FileSize $destination
                    
                    #build array of software for inventory
                    $SoftObject += new-object psobject -property @{
                        FilePath=$destination
                        Version=$Version
                        File=$Filename
                        Publisher=$Publisher
                        Product=$Product
                        Arch=$ArchLabel
                        Language=''
                        FileType=$ExtensionType
                        ProductType=''
                        Downloaded=$downloaded
                        Description=$Description
                        DownloadDate=$CreatedDate
                        Size=$FileSize
                    }
                }
            }
        }
        catch {
            Write-LogEntry ("Unable to download [{0}]. {1} Check Line: {2}" -f $Product,$_.Exception.Message,$_.InvocationInfo.ScriptLineNumber)  -Severity 3 -Source ${CmdletName} -Outhost
        }
    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }
}

# VLC (x86 & x64) - DOWNLOAD
#==================================================
Function Get-VLCPlayer {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,
        
        [parameter(Mandatory=$true)]
        [string]$FolderPath,

        [parameter(Mandatory=$false)]
        [ValidateSet('x86', 'x64')]
        [string]$Arch,

        [parameter(Mandatory=$false)]
        [switch]$Overwrite,

        [parameter(Mandatory=$false)]
        [switch]$Cleanup,

        [parameter(Mandatory=$false)]
        [switch]$ReturnDetails 

	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        $Publisher = "VideoLan"
        $Product = "VLC Media Player"

        [System.Uri]$SourceURL = "http://www.videolan.org/vlc/"
        [string]$DownloadURL = "https://get.videolan.org/vlc"

        Try{
            ## -------- CRAWL WEBSITE ----------
            #don't use basic web parsing when get html elements
            $content = Invoke-WebRequest $SourceURL -ErrorAction Stop
            start-sleep 3
            
            ## -------- PARSE DESCRIPTION ----------
            $Description = Get-WebContentHeader -WebContent $content -Property Description

            ## -------- PARSE VESION ----------
            $GetVersion = $content.AllElements | Where-Object{$_.id -like "downloadVersion*"} | Select-Object -ExpandProperty outerText
            $Version = $GetVersion.Trim()
            Write-LogEntry ("{0}'s latest version is: [{1}]" -f $Product,$Version) -Severity 1 -Source ${CmdletName} -Outhost

            ## -------- BUILD ROOT FOLDER ----------
            $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
            If( !(Test-Path $DestinationPath)){
                New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
            }

            #Remove all folders and files except the latest if they exist
            If($Cleanup){
                Get-ChildItem -Path $DestinationPath | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
                    Remove-Item $_.fullname -Recurse -Force | Out-Null
                    Write-LogEntry ("Removed File: [{0}]" -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
                }
            }

            #build Destination folder based on version
            New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null

            switch($Arch){
                'x86' {$DownloadLinks = "$DownloadURL/$Version/win32/vlc-$Version-win32.exe"}
                'x64' {$DownloadLinks = "$DownloadURL/$Version/win64/vlc-$Version-win64.exe"}

                default {$DownloadLinks = "$DownloadURL/$Version/win32/vlc-$Version-win32.exe",
                                        "$DownloadURL/$Version/win64/vlc-$Version-win64.exe" }
            }

            Foreach($link in $DownloadLinks){
                #build Download link from Root URL (if Needed)
                $DownloadLink = $link
                Write-LogEntry ("Validating Download Link: [{0}]" -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

                $Filename = $link | Split-Path -Leaf
                $destination = $DestinationPath + "\" + $Version + "\" + $Filename

                #if match is found, set label
                If($Filename -match '-win64'){
                    $ArchLabel = "x64"
                }Else{
                    $ArchLabel = "x86"
                }

                $ExtensionType = [System.IO.Path]::GetExtension($fileName)

                If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                    Write-LogEntry ("File found: [{0}]. Ignoring download" -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                }
                Else{
                    ## -------- DOWNLOAD SOFTWARE ----------
                    If((Test-Path $destination -ErrorAction SilentlyContinue) -and $Overwrite){$OverwriteMsg = "File found, Overwriting! "}Else{$OverwriteMsg = ""}
                    Try{
                        Write-LogEntry ("{0}Attempting to download: [{1}]..." -f $OverwriteMsg,$Filename) -Severity 1 -Source ${CmdletName} -Outhost

                        Initialize-FileDownload -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                        #$wc.DownloadFile($link, $destination) 
                        Write-LogEntry ("Succesfully downloaded: {0} ({1}) to [{2}]" -f $Product,$ArchLabel,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                        $downloaded=$True
                    } 
                    Catch {
                        Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                        $downloaded=$False
                    }
                }
        
                #Build Object if exists
                If(Test-Path $destination){
                    #grab the date on the file 
                    $CreatedDate = Get-ChildItem $destination | Select-Object -ExpandProperty CreationTime | Get-Date -f "yyyy-MM-dd"
                    $FileSize = Get-FileSize $destination
                    
                    #build array of software for inventory
                    $SoftObject += new-object psobject -property @{
                        FilePath=$destination
                        Version=$Version
                        File=$Filename
                        Publisher=$Publisher
                        Product=$Product
                        Arch=$ArchLabel
                        Language=''
                        FileType=$ExtensionType
                        ProductType=''
                        Downloaded=$downloaded
                        Description=$Description
                        DownloadDate=$CreatedDate
                        Size=$FileSize
                    }
                }
            }
        }
        catch {
            Write-LogEntry ("Unable to download [{0}]. {1} Check Line: {2}" -f $Product,$_.Exception.Message,$_.InvocationInfo.ScriptLineNumber)  -Severity 3 -Source ${CmdletName} -Outhost
        }
    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }
}

# GIT (x86 & x64) - DOWNLOAD
#==================================================
function Get-Git {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,

        [parameter(Mandatory=$true)]
        [string]$FolderPath,

        [parameter(Mandatory=$false)]
        [ValidateSet('x86', 'x64')]
        [string]$Arch,

        [parameter(Mandatory=$false)]
        [switch]$Overwrite,

        [parameter(Mandatory=$false)]
        [switch]$Cleanup,

        [parameter(Mandatory=$false)]
        [switch]$ReturnDetails 

	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        $Publisher = "Git"
        $Product = "Git Bash"

        [System.Uri]$SourceURL = "https://git-scm.com"

        Try{
            ## -------- CRAWL WEBSITE ----------
            #don't use basic web parsing when get html elements
            $content = Invoke-WebRequest $SourceURL -ErrorAction Stop
            start-sleep 3
            
            ## -------- PARSE DESCRIPTION ----------
            $Description = Get-WebContentHeader -WebContent $content -Property Description

            ## -------- PARSE VERSION ----------
            $GetVersion = $content.AllElements | Where-Object{$_."data-win"} | Select-Object -ExpandProperty data-win
            $Version = $GetVersion.Trim()

            Write-LogEntry ("{0}'s latest version is: [{1}]" -f $Product,$Version) -Severity 1 -Source ${CmdletName} -Outhost

            ## -------- BUILD ROOT FOLDER ----------
            $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
            If( !(Test-Path $DestinationPath)){
                New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
            }
        
            #Remove all folders and files except the latest if they exist
            If($Cleanup){
                Get-ChildItem -Path $DestinationPath | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
                    Remove-Item $_.fullname -Recurse -Force | Out-Null
                    Write-LogEntry ("Removed File: [{0}]" -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
                }
            }
            
            #build Destination folder based on version
            New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null
            
            $DownloadSourceContent = Invoke-WebRequest "$SourceURL/download/win"
            $AllDownloads = Get-Hyperlinks -content [string]$DownloadSourceContent | Where-Object{$_.Href -like "*$Version*"}

            switch($Arch){
                'x86' {$DownloadLinks = $AllDownloads | Where-Object{$_.Text -like "32-bit*"}| Select-Object -First 1}
                'x64' {$DownloadLinks = $AllDownloads | Where-Object{$_.Text -like "64-bit*"}| Select-Object -First 1}

                default {$DownloadLinks = $AllDownloads | Where-Object{$_.Text -like "*bit*"}| Select-Object -First 2}
            }

            Foreach($link in $DownloadLinks){
                #build Download link from Root URL (if Needed)
                $DownloadLink = $link.href
                Write-LogEntry ("Validating Download Link: [{0}]" -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

                $Filename = $DownloadLink| Split-Path -Leaf
                $destination = $DestinationPath + "\" + $Version + "\" + $Filename

                #if match is found, set label
                If($Filename -match '64-bit'){
                    $ArchLabel = "x64"
                }Else{
                    $ArchLabel = "x86"
                }

                $ExtensionType = [System.IO.Path]::GetExtension($fileName)

                If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                    Write-LogEntry ("File found: [{0}]. Ignoring download" -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                }
                Else{
                    ## -------- DOWNLOAD SOFTWARE ----------
                    Try{
                        Write-LogEntry ("Attempting to download: [{0}]..." -f $Filename) -Severity 1 -Source ${CmdletName} -Outhost

                        Initialize-FileDownload -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                        #$wc.DownloadFile($link, $destination) 
                        Write-LogEntry ("Succesfully downloaded: {0} ({1}) to [{2}]" -f $Product,$ArchLabel,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                        $downloaded=$True
                    } 
                    Catch {
                        Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                        $downloaded=$False
                    }
                }
        
                #Build Object if exists
                If(Test-Path $destination){
                    #grab the date on the file 
                    $CreatedDate = Get-ChildItem $destination | Select-Object -ExpandProperty CreationTime | Get-Date -f "yyyy-MM-dd"
                    $FileSize = Get-FileSize $destination
                    
                    #build array of software for inventory
                    $SoftObject += new-object psobject -property @{
                        FilePath=$destination
                        Version=$Version
                        File=$Filename
                        Publisher=$Publisher
                        Product=$Product
                        Arch=$ArchLabel
                        Language=''
                        FileType=$ExtensionType
                        ProductType=''
                        Downloaded=$downloaded
                        Description=$Description
                        DownloadDate=$CreatedDate
                        Size=$FileSize
                    }
                }
            }
        }
        catch {
            Write-LogEntry ("Unable to download [{0}]. {1} Check Line: {2}" -f $Product,$_.Exception.Message,$_.InvocationInfo.ScriptLineNumber)  -Severity 3 -Source ${CmdletName} -Outhost
        }
    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }
}


# POWERBI (x86 & x64) - DOWNLOAD
#==================================================
function Get-PowerBI {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,

        [parameter(Mandatory=$false)]
        [string]$FolderPath,

        [parameter(Mandatory=$false)]
        [ValidateSet('x86', 'x64')]
        [string]$Arch,

        [parameter(Mandatory=$false)]
        [switch]$Overwrite,

        [parameter(Mandatory=$false)]
        [switch]$Cleanup,

        [parameter(Mandatory=$false)]
        [switch]$ReturnDetails 
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        $Publisher = "Microsoft"
        $Product = "PowerBI Desktop"
        $ShorttName = "PBIDesktop"
        $Language = "en-us"

        If(!$FolderPath){$FolderPath = $Product}

        [System.Uri]$SourceURL = "https://powerbi.microsoft.com/$Language/downloads/"
        #ttps://download.microsoft.com/download/9/B/A/9BAEFFEF-1A68-4102-8CDF-5D28BFFE6A61/
        #https://www.microsoft.com/en-us/download/confirmation.aspx?id=45331&6B49FDFB-8E5B-4B07-BC31-15695C5A2143=1
        [String]$DownloadURL = "https://www.microsoft.com/$Language/download/"

        Try{
            ## -------- CRAWL SOURCE AS RAW CONTENT ----------
            #don't use basic web parsing when get html elements
            $content = Invoke-WebRequest $SourceURL -ErrorAction Stop
            start-sleep 3

            ## -------- PARSE HREF LINKS ----------
            $DetailLink = Get-HrefMatches -content [string]$content | Where-Object {$_ -like "*details.aspx?*"} | Select-Object -First 1

            ## -------- FIND LINK ID ----------
            $Null = $DetailLink -match ".*?=(\d+)"
            $LinkID = $Matches[1]

            ## -------- PARSE VERSION ----------
            $DetailContent = Invoke-WebRequest $DetailLink -ErrorAction Stop 
            $Version = $DetailContent.RawContent | Select-String -Pattern '(\d+\.)(\d+\.)(\d+\.)(\d+)' -AllMatches | Select-Object -ExpandProperty matches | Select-Object -ExpandProperty value
            
            Write-LogEntry ("{0}'s latest version is: [{1}]" -f $Product,$Version) -Severity 1 -Source ${CmdletName} -Outhost

            ## -------- FIND FILE LINKS ----------
            $ConfirmationLink = $DownloadURL + "/confirmation.aspx?id=$LinkID"
            $ConfirmationContent = Invoke-WebRequest $ConfirmationLink -ErrorAction Stop
            $AllDownloads = Get-HrefMatches -content [string]$ConfirmationContent  | Where-Object {$_ -match $ShorttName} | Select-Object -Unique
            
            switch($Arch){
                'x86' {$DownloadLinks = $AllDownloads | Where-Object{$_ -notmatch "x64"}| Select-Object -First 1}
                'x64' {$DownloadLinks = $AllDownloads | Where-Object{$_ -match "x64"}| Select-Object -First 1}

                default {$DownloadLinks = $AllDownloads | Select-Object -First 2}
            }

            ## -------- BUILD ROOT FOLDER ----------
            $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
            If( !(Test-Path $DestinationPath)){
                New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
            }

            #Remove all folders and files except the latest if they exist
            If($Cleanup){
                Get-ChildItem -Path $DestinationPath | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
                    Remove-Item $_.fullname -Recurse -Force | Out-Null
                    Write-LogEntry ("Removed File: [{0}]" -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
                }
            }
            
            #build Destination folder based on version
            New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null

            Foreach($link in $DownloadLinks){
                #build Download link from Root URL (if Needed)
                $DownloadLink = $link
                Write-LogEntry ("Validating Download Link: [{0}]" -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

                $Filename = $DownloadLink| Split-Path -Leaf
                $destination = $DestinationPath + "\" + $Version + "\" + $Filename

                #if match is found, set label
                If($Filename -match 'x64'){
                    $ArchLabel = "x64"
                }Else{
                    $ArchLabel = "x86"
                }

                $ExtensionType = [System.IO.Path]::GetExtension($fileName)

                If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                    Write-LogEntry ("File found: [{0}]. Ignoring download" -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                }
                Else{
                    ## -------- DOWNLOAD SOFTWARE ----------
                    Try{
                        Write-LogEntry ("Attempting to download: [{0}]..." -f $Filename) -Severity 1 -Source ${CmdletName} -Outhost

                        Initialize-FileDownload -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                        #$wc.DownloadFile($link, $destination) 
                        Write-LogEntry ("Succesfully downloaded: {0} ({1}) to [{2}]" -f $Product,$ArchLabel,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                        $downloaded=$True
                    } 
                    Catch {
                        Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                        $downloaded=$False
                    }
                }
        
                #Build Object if exists
                If(Test-Path $destination){
                    #grab the date on the file 
                    $CreatedDate = Get-ChildItem $destination | Select-Object -ExpandProperty CreationTime | Get-Date -f "yyyy-MM-dd"
                    $FileSize = Get-FileSize $destination
                    
                    #build array of software for inventory
                    $SoftObject += new-object psobject -property @{
                        FilePath=$destination
                        Version=$Version
                        File=$Filename
                        Publisher=$Publisher
                        Product=$Product
                        Arch=$ArchLabel
                        Language=''
                        FileType=$ExtensionType
                        ProductType=''
                        Downloaded=$downloaded
                        Description=$Description
                        DownloadDate=$CreatedDate
                        Size=$FileSize
                    }
                }
            }
        }
        catch {
            Write-LogEntry ("Unable to download [{0}]. {1} Check Line: {2}" -f $Product,$_.Exception.Message,$_.InvocationInfo.ScriptLineNumber)  -Severity 3 -Source ${CmdletName} -Outhost
        }
    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }
}
#==================================================
# MAIN - DOWNLOAD 3RD PARTY SOFTWARE
#==================================================
#Create secure channel
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

## Load the System.Web DLL so that we can decode URLs
Add-Type -Assembly System.Web

#$wc = New-Object System.Net.WebClient
# Proxy-Settings
#$wc.Proxy = [System.Net.WebRequest]::DefaultWebProxy
#$wc.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials

#Get-Process "firefox" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
#Get-Process "iexplore" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
#Get-Process "Openwith" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$list = @()
$list += Get-Java8 -RootPath $SoftwarePath -FolderPath 'Java 8' -ReturnDetails -Overwrite:$OverwriteFiles -Cleanup:$CleanupFiles
$list += Get-JDK -RootPath $SoftwarePath -FolderPath 'JDK' -ReturnDetails -Overwrite:$OverwriteFiles -Cleanup:$CleanupFiles
$list += Get-ReaderDC -RootPath $SoftwarePath -FolderPath 'ReaderDC' -AllLangToo -UpdatesOnly -ReturnDetails -Overwrite:$OverwriteFiles -Cleanup:$CleanupFiles
#$list += Get-AcrobatPro -RootPath $SoftwarePath -FolderPath 'AcrobatDCPro' -AllLangToo -ReturnDetails -Overwrite:$OverwriteFiles -Cleanup:$CleanupFiles
$list += Get-Flash -RootPath $SoftwarePath -FolderPath 'Flash' -ReturnDetails -Overwrite:$OverwriteFiles -Cleanup:$CleanupFiles
$list += Get-Shockwave -RootPath $SoftwarePath -FolderPath 'Shockwave' -ReturnDetails -Overwrite:$OverwriteFiles -Cleanup:$CleanupFiles
$list += Get-Git -RootPath $SoftwarePath -FolderPath 'Git' -ReturnDetails -Overwrite:$OverwriteFiles -Cleanup:$CleanupFiles
$list += Get-Firefox -RootPath $SoftwarePath -FolderPath 'Firefox' -Type ESR -Installer exe -ReturnDetails -Overwrite:$OverwriteFiles -Cleanup:$CleanupFiles
$list += Get-Firefox -RootPath $SoftwarePath -FolderPath 'Firefox' -Type ESR -Installer msi -ReturnDetails -Overwrite:$OverwriteFiles -Cleanup:$CleanupFiles
$list += Get-NotepadPlusPlus -RootPath $SoftwarePath -FolderPath 'NotepadPlusPlus' -ReturnDetails -Overwrite:$OverwriteFiles -Cleanup:$CleanupFiles
$list += Get-7Zip -RootPath $SoftwarePath -FolderPath '7Zip' -ReturnDetails -Overwrite:$OverwriteFiles -Cleanup:$CleanupFiles
$list += Get-VLCPlayer -RootPath $SoftwarePath -FolderPath 'VLC Player' -ReturnDetails -Overwrite:$OverwriteFiles -Cleanup:$CleanupFiles
$list += Get-Chrome -RootPath $SoftwarePath -FolderPath 'Chrome' -ReturnDetails -Overwrite:$OverwriteFiles -Cleanup:$CleanupFiles
$list += Get-PowerBI -RootPath $SoftwarePath -FolderPath 'PowerBI' -ReturnDetails -Overwrite:$OverwriteFiles -Cleanup:$CleanupFiles

$list | Export-Clixml $SoftwarePath\softwarelist.xml

Write-LogEntry ("Completed downloading updates to {0}" -f $SoftwarePath) -Outhost