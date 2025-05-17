param(
    [Parameter(Mandatory=$true)]
    [string]$PAToken,

    [string]$AzureDevOpsURL = 'https://dev.azure.com/FHTW-DEVSEC/',
    [string]$AzureDevOpsProjectName = 'DEVSEC',
    [string]$AzureDevOpsEnvironmentName = 'MTCG-Prod-VMs',
    [string]$AgentDownloadUrl = 'https://download.agent.dev.azure.com/agent/4.255.0/vsts-agent-win-x64-4.255.0.zip'
)

$ErrorActionPreference = "Stop"

# Verbose logging function
function Write-Log {
    param ([string]$Message)
    Write-Host "AGENT_SCRIPT_LOG: $Message"
}

Write-Log "Starting Azure DevOps Agent registration script."

# Check for Administrator privileges
Write-Log "Checking for Administrator privileges..."
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Log "Error: Script must be run in an administrator PowerShell prompt."
    throw "Run command in an administrator PowerShell prompt"
}
Write-Log "Administrator privileges confirmed."

# Check PowerShell version
Write-Log "Checking PowerShell version..."
if ($PSVersionTable.PSVersion -lt (New-Object System.Version("3.0"))) {
    Write-Log "Error: Minimum PowerShell version 3.0 required. Current version: $($PSVersionTable.PSVersion)"
    throw "The minimum version of Windows PowerShell that is required by the script (3.0) does not match the currently running version of Windows PowerShell."
}
Write-Log "PowerShell version $($PSVersionTable.PSVersion) confirmed."

# Create agent installation directory
$agentInstallDir = "$env:SystemDrive\azagent"
Write-Log "Ensuring agent installation directory exists: $agentInstallDir"
if (-NOT (Test-Path $agentInstallDir)) {
    mkdir $agentInstallDir
    Write-Log "Created directory: $agentInstallDir"
}
cd $agentInstallDir
Write-Log "Changed current directory to: $PWD"

# Create unique subfolder for the agent
$agentSubFolder = ''
for ($i = 1; $i -lt 100; $i++) {
    $destFolder = "A$($i)"
    if (-NOT (Test-Path $destFolder)) {
        mkdir $destFolder
        $agentSubFolder = $destFolder
        Write-Log "Created agent subfolder: $agentSubFolder"
        cd $agentSubFolder
        Write-Log "Changed current directory to: $PWD"
        break
    }
}

if ([string]::IsNullOrEmpty($agentSubFolder)) {
    Write-Log "Error: Could not create a unique agent subfolder in $agentInstallDir."
    throw "Could not create a unique agent subfolder."
}

$agentZipPath = Join-Path -Path $PWD -ChildPath "agent.zip"
Write-Log "Agent ZIP path set to: $agentZipPath"

# Download agent
$DefaultProxy = [System.Net.WebRequest]::DefaultWebProxy
$securityProtocolBackup = [Net.ServicePointManager]::SecurityProtocol
try {
    Write-Log "Setting security protocol for download (TLS 1.2 preferred)."
    # Ensure TLS 1.2 is enabled, as older protocols are being deprecated.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    
    $WebClient = New-Object Net.WebClient
    if ($DefaultProxy -and (-not $DefaultProxy.IsBypassed($AgentDownloadUrl))) {
        $WebClient.Proxy = New-Object Net.WebProxy($DefaultProxy.GetProxy($AgentDownloadUrl).OriginalString, $True)
        Write-Log "Using system proxy: $($WebClient.Proxy.Address)"
    }

    Write-Log "Downloading Azure DevOps Agent from $AgentDownloadUrl to $agentZipPath..."
    $WebClient.DownloadFile($AgentDownloadUrl, $agentZipPath)
    Write-Log "Agent downloaded successfully."
}
catch {
    Write-Log "Error: Failed to download agent. $($_.Exception.Message) - $($_.Exception.InnerException.Message)"
    throw $_
}
finally {
    Write-Log "Restoring original security protocol."
    [Net.ServicePointManager]::SecurityProtocol = $securityProtocolBackup
}

# Extract agent
Write-Log "Extracting agent from $agentZipPath to $PWD..."
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($agentZipPath, "$PWD")
Write-Log "Agent extracted successfully."

# Configure agent
$agentName = $env:COMPUTERNAME
$workDir = '_work'

Write-Log "Configuring agent with the following parameters:"
Write-Log "  Agent Name: $agentName"
Write-Log "  Environment Name: $AzureDevOpsEnvironmentName"
Write-Log "  Azure DevOps URL: $AzureDevOpsURL"
Write-Log "  Project Name: $AzureDevOpsProjectName"
Write-Log "  Work Directory: $workDir"
Write-Log "  Authentication Type: PAT (Token will not be logged)"

if ([string]::IsNullOrWhiteSpace($PAToken)) {
    Write-Log "Error: PAToken parameter is null or empty. Agent cannot be configured."
    throw "PAToken is null or empty. Cannot configure agent."
}

$configScriptPath = Join-Path -Path $PWD -ChildPath 'config.cmd'
$configArgs = @(
    '--environment',
    '--environmentname', $AzureDevOpsEnvironmentName,
    '--agent', $agentName,
    '--runasservice',        # Ensures the agent runs as a Windows service
    '--work', $workDir,
    '--url', $AzureDevOpsURL,
    '--projectname', $AzureDevOpsProjectName,
    '--auth', 'PAT',
    '--token', $PAToken,
    '--unattended'          # Important for non-interactive setup
)

Write-Log "Executing agent configuration: $configScriptPath $($configArgs -join ' ')" # Exercise caution logging this if PAT was accidentally included in $configArgs for logging
                                                                                    # Current $configArgs setup is safe as $PAToken is separate.
try {
    # Using Start-Process to ensure proper execution of .cmd and capture exit code if needed.
    $process = Start-Process -FilePath $configScriptPath -ArgumentList $configArgs -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0) {
        Write-Log "Error: Agent configuration script (config.cmd) exited with code $($process.ExitCode)."
        throw "Agent configuration failed with exit code $($process.ExitCode)."
    }
    Write-Log "Agent configuration script (config.cmd) completed successfully."
}
catch {
    Write-Log "Error: Exception during agent configuration. $($_.Exception.Message)"
    throw $_
}

# Clean up downloaded agent zip file
Write-Log "Removing agent zip file: $agentZipPath"
Remove-Item $agentZipPath -ErrorAction SilentlyContinue -Force
Write-Log "Agent zip file removed."

Write-Log "Azure DevOps Agent registration script finished successfully."
