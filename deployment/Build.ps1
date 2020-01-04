[CmdletBinding()]
Param(
    [Parameter()]
    [string] $ProjectName = 'SVGThumbnailExtension',

    [Parameter()]
    [ValidateSet('release', 'debug')]
    [string] $Configuration = 'release',

    [Parameter()]
    [ValidateSet('x86', 'x64')]
    [string] $Architecture = 'x64',

    [Parameter()]
    [ValidateSet('2015', '2017', '2019')]
    [string] $VSVersion = '2017',

    [Parameter()]
    [ValidateSet('Community', 'Professional', 'Enterprise', 'BuildTools')]
    [string] $VSEdition = 'Community',
    
    [Parameter()]
    [string] $WinSdk = '10.0.17763.0',
    
    [Parameter()]
    [string] $QtVersion = '5.12.*',
    
    [Parameter()]
    [string] $QtInstallPath = 'C:\Qt\',
    
    [Parameter()]
    [string] $InnoSetupPath = 'C:\Program Files (x86)\Inno Setup 6'
)

$ErrorActionPreference = 'stop'

Import-Module (Join-Path $PSScriptRoot 'Utils.psm1')

Write-Verbose "Setting up development environment."

$rootFolder = Resolve-Path (Join-Path  $PSScriptRoot '..')

$distDir = Join-Path $rootFolder "var/dist/$Architecture/$Configuration"
$binary = Join-Path $distDir "$ProjectName.dll"
$buildDir = Join-Path $rootFolder "var/build/$Architecture"
$projectFile = Resolve-Path (Join-Path $rootFolder "$ProjectName/$ProjectName.pro")
$licenseDir = Join-Path $rootFolder 'var/licenses'

$vsArchitectureMap = @{
    'x86' = 'x86';
    'x64' = 'amd64';
}

Use-VisualStudioBuildTools `
    -Version $VSVersion `
    -Edition $VSEdition `
    -Architecture $vsArchitectureMap[$Architecture] `
    -Sdk $WinSdk `
    -Spectre `
    -Verbose

# NOTE: I know it's not right. We'll fix it later.
$qtArchitectureMap = @{
    'x86' = "msvc$VSVersion";
    'x64' = "msvc${VSVersion}_64";
}

$qtParams = @{ }
if ($QtInstallPath) {
    $qtParams["QtInstallPath"] = $QtInstallPath
}

Use-QtBuildTools `
    -Version $QtVersion `
    -Platform $qtArchitectureMap[$Architecture] `
    @qtParams `
    -Verbose

Use-InnoSetup -InstallPath $InnoSetupPath

Write-Verbose "Building application."

New-Item -Path $distDir -ItemType Directory -Force
New-Item -Path $buildDir -ItemType Directory -Force

Push-Location $buildDir

try {
    qmake "CONFIG+=$Configuration" "DLLDESTDIR=$distDir" $projectFile | Write-Verbose
    Assert-LastExitCode -Message "Failed to execute qmake to generate Makefiles"
    nmake clean | Write-Verbose
    Assert-LastExitCode -Message "Failed to clean project"
    nmake | Write-Verbose
    Assert-LastExitCode -Message "Failed to build project"
}
finally {
    Pop-Location
}

Write-Verbose "Deploying Qt dependencies for the application."

windeployqt.exe `
    --no-translations `
    --no-quick-import `
    --no-system-d3d-compiler `
    --no-angle `
    --no-opengl-sw `
    $binary `
    | Write-Verbose
Assert-LastExitCode "Failed to deploy Qt dependencies for the built binary."

Write-Verbose "Cleaning up unused Qt plugins."
$unusedPlugins = @(
    'iconengines',
    'imageformats'
)
foreach($plugin in $unusedPlugins) {
    Remove-Item (Join-Path $distDir $plugin) -Recurse -Force
}

Write-Verbose "Gathering licenses"

New-Item -Path $licenseDir -ItemType Directory -Force
Copy-Item -Path (Join-Path $QtInstallPath 'Licenses\LICENSE') -Destination (Join-Path $licenseDir "Qt.txt") -Force

Write-Verbose "Building installer"

Push-Location $rootFolder
try {
    $issFile = Join-Path $rootFolder "deployment/${ProjectName}.iss";
    iscc "/darch=$Architecture" "$issFile" | Write-Verbose
}
finally {
    Pop-Location
}
