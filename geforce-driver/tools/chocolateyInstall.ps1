$packageName = 'geforce-driver'
$fileType = 'exe'
$silentArgs = '-s -noreboot'
$packageParameters = $env:chocolateyPackageParameters

if ($packageParameters -like '*clean*') {
  $silentArgs += ' -clean'
}

$scriptDir = $(Split-Path -parent $MyInvocation.MyCommand.Definition)
Import-Module (Join-Path $scriptDir "functions.ps1")

$url = Get-DriverUrl

if ($url) {
  $tempDir = Join-Path $env:TEMP "$packageName"
  if (![System.IO.Directory]::Exists($tempDir)) { [System.IO.Directory]::CreateDirectory($tempDir) | Out-Null }
  $zip = Join-Path $tempDir "geforcedriver.zip"
  Get-ChocolateyWebFile $packageName $zip $url
  $installerDir = Join-Path $tempDir "Installer"
  Create-EmptyDirectory $installerDir
  Get-ChocolateyUnzip $zip $installerDir
  if ($packageParameters -like '*nogfexp*') {
    $path = Join-Path $installerDir "GFExperience"
    Remove-Recursively $path
    $path = Join-Path $installerDir "setup.cfg"
    $xml = [xml](Get-Content $path)
    foreach ($package in $xml.setup.install.'sub-package') {
      if ($package.name -eq "Display.GFExperience") {
        $package.ParentNode.RemoveChild($package)
      }
    }
    $xml.Save($path)
  }
  $file = Join-Path $installerDir 'setup.exe'
  Install-ChocolateyInstallPackage $packageName $fileType $silentArgs $file
  Remove-Recursively $installerDir
}