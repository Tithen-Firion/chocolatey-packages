function Get-OsCode {
  return [string][Environment]::OSVersion.Version.Major + '.' + [string][Environment]::OSVersion.Version.Minor
}

function Get-GraphicsCardType ([string] $name) {
  if ($name -match '(M(X|\s+(LE|GTX|GTS|GS|GT|G))?$|GeForce Go)') {
    return 'notebook'
  } else {
    return 'desktop'
  }
}

function Get-DriverVersion ($card) {
  $infFilename = $card.InfFilename.Trim()
  $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SOFTWARE\NVIDIA Corporation\Installer2\Drivers\")
  if ($key) {
    $value = $key.GetValue($infFilename)
    if ($value) {
      $version = $value -replace ".+\/([\d\.]+).*\r?\n.*",'$1'
      if ($version -match "^[\d\.]+$") {
        return $version
      }
    }
  }
  return $Null
}

function Get-GraphicsCardInfo {
  $cards = @(gwmi win32_VideoController)
  foreach ($card in $cards) {
    $name = $card.Name.Trim()
    if ($name -match '^NVIDIA') {
      $name = $name.Replace('NVIDIA', '').Trim()
      $type = Get-GraphicsCardType $name
      $driverVersion = Get-DriverVersion $card
      return $name, $type, $driverVersion
    }
  }
  return $Null, $Null, $Null
}

function Get-SearchData ([string] $typeID, [string] $parentID) {
  # $typeID - 2 for series, 3 for card, 4 for system
  $url = 'http://www.nvidia.com/Download/API/lookupValueSearch.aspx?TypeID=' + $typeID + '&ParentID=' + $parentID
  $xml = Invoke-RestMethod -Uri $url
  return $xml.LookupValueSearch.LookupValues.LookupValue
}

function Get-Driver ([string] $seriesID, [string] $cardID, [string] $osID) {
  $url = "http://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php"
  $url += "?languageCode=1033&beta=0&dltype=-1&isWHQL=1&numberOfResults=1&sort1=0&func=DriverManualLookup"
  $url += "&psid=" + $seriesID + "&pfid=" + $cardID + "&osID=" + $osID
  $json = Invoke-RestMethod -Uri $url
  $info = $json.IDS[0].downloadInfo
  if ($info.Success -eq 1) {
    return $info.DownloadURL, $info.DetailsURL, $info.Version
  }
  return $Null, $Null, $Null
}

function Get-Reboot {
  $keys = (Get-ChildItem HKLM:\SOFTWARE -ea SilentlyContinue)
  foreach ($key in $keys) {
    if ($key.Name -match 'NVIDIA_RebootNeeded') {
      return $True
    }
  }
  return $False
}

function Remove-Recursively ([string] $path) {
  if ([System.IO.Directory]::Exists($path)) {
    $longPath = (Get-Item -LiteralPath $path).FullName
    Remove-Item $longPath -Recurse -Force
  }
}

function Create-EmptyDirectory ([string] $path) {
  Remove-Recursively $path
  [System.IO.Directory]::CreateDirectory($path) | Out-Null
}

function Get-DriverUrl {
  if(Get-Reboot) {
    Throw ("You need to restart computer before this installation.")
  }

  $cardName, $cardType, $currentDriverVersion = Get-GraphicsCardInfo
  $osCode = Get-OsCode
  $osBitness = [string](Get-ProcessorBits) + '-bit'

  $cardID = $Null
  $data = Get-SearchData 2 1
  foreach ($series in $data) {
    # limit series to desktop/notebook
    if ($cardType -eq 'notebook') {
      if ($series.Name -notlike '*notebook*') { continue }
    } else {
      if ($series.Name -like '*notebook*') { continue }
    }
    
    $seriesID = $series.Value
    $seriesCards = Get-SearchData 3 $seriesID
    foreach ($card in $seriesCards) {
      $name = $card.Name.Replace('NVIDIA', '').Trim()
      if ($name -eq $cardName) {
        $cardID = $card.Value
        break
      } elseif ($name -like "*/*") {
        if ((($name -replace "(\/|nForce).*$","").Trim() -eq $cardName) -or `
            (($name -replace "(?:[^\s]+\/|(?:[^\s]+\s+){2}\/|.*?(nForce))",'' -replace "\s+"," ").Trim() -eq $cardName)) {
          
          $cardID = $card.Value
          break
        }
      }
    }
    if ($cardID -ne $Null) { break }
  }
  if ($cardID -eq $Null) {
    Throw ("Could not find matching graphics card. " + $cardName)
  }

  $osID = $Null
  $oses = Get-SearchData 4 $seriesID
  foreach ($os in $oses) {
    if (($os.Code -eq $osCode) -and ($os.Name -match $osBitness)) {
      $osID = $os.Value
      break
    }
  }
  if ($osID -ne $Null) {
    $downloadUrl, $detailsUrl, $driverVersion = Get-Driver $seriesID $cardID $osID
  }

  if (($osID -eq $Null) -or ($downloadUrl -eq $Null)) {
    Throw ("Could not find driver for your OS. " + $cardName + "; " + $osCode + " " + $osBitness)
  }

  if ($currentDriverVersion -eq $driverVersion) {
    Write-Host "Most recent driver ($driverVersion) already installed."
    return $Null
  }
  #Write-Host $detailsUrl
  return $downloadUrl
}
